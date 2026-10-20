#!/usr/bin/env python3
"""Load generator for the [C] - vLLM Cache & Queue Pressure dashboard.

Sends streaming OpenAI-compatible completion requests to a vLLM (or llm-d
inference-sim) endpoint so the dashboard panels have live data:

    KV cache utilization %       <- vllm:kv_cache_usage_perc
    Inter-token latency p90 (s)  <- vllm:inter_token_latency_seconds_bucket
    Prefill vs decode p90 (s)    <- vllm:request_{prefill,decode}_time_seconds_bucket
    Waiting requests             <- vllm:num_requests_waiting

Stdlib only. TLS endpoints with self-signed certificates (llm-d inference sim)
are handled by default.

Usage
-----
# 1. Reach the model from your laptop (or run the generator in-cluster - see
#    vllm-load-gen-pod.yaml):
oc -n <model-namespace> port-forward svc/<model-service> 18000:8000

# 2. Generate load:
python3 vllm-load-gen.py --base-url https://localhost:18000 --duration 300
python3 vllm-load-gen.py --base-url https://localhost:18000 --concurrency 16 --ramp 120

# 3. Watch the dashboard in the RHOAI console (Observe -> Observability).
#    The rate() panels need a scrape or two: give them ~1 minute.

Load pattern
------------
Steady mode keeps `--concurrency` workers busy for `--duration` seconds.
Burst mode (--burst-every N) fires a synchronized wave of one request per
worker every N seconds on a shared clock - long requests from an earlier wave
overlap into later ones, stacking queue pressure until `num_requests_waiting`
climbs above zero.

Prompts are `--prompt-words` words long (exercises prefill; KV cache usage
rises with prompt + generation length) and each request generates up to
`--max-tokens` streamed tokens.
"""

import argparse
import http.client
import json
import ssl
import sys
import threading
import time
from urllib.parse import urlparse

STOP = threading.Event()
STATS = {"ok": 0, "err": 0, "tokens": 0, "e2e": []}
STATS_LOCK = threading.Lock()


def parse_args():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--base-url", default="https://localhost:8000",
                   help="scheme://host:port of the model endpoint (default %(default)s)")
    p.add_argument("--model", default=None,
                   help="model name; defaults to the first one the server reports")
    p.add_argument("--concurrency", type=int, default=8,
                   help="number of concurrent workers (default %(default)s)")
    p.add_argument("--duration", type=int, default=120,
                   help="seconds of load (default %(default)s)")
    p.add_argument("--max-tokens", type=int, default=150,
                   help="generation length per request (default %(default)s)")
    p.add_argument("--prompt-words", type=int, default=200,
                   help="prompt length in words, exercises prefill (default %(default)s)")
    p.add_argument("--burst-every", type=int, default=0,
                   help="synchronized request wave every N seconds; 0 disables (default %(default)s)")
    p.add_argument("--ramp", type=int, default=0,
                   help="seconds of load per on/off cycle, e.g. --ramp 120 alternates 120s of load with 120s idle - "
                        "makes the rate() panels rise and fall over time (default 0 = steady)")
    p.add_argument("--verify-tls", action="store_true",
                   help="verify TLS certificates (default: skip, for self-signed sim certs)")
    return p.parse_args()


def make_connection(parsed, verify_tls):
    """One connection per worker; HTTP for plain, HTTPS (optionally unverified) for TLS."""
    if parsed.scheme == "https":
        ctx = ssl.create_default_context()
        if not verify_tls:
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
        return http.client.HTTPSConnection(parsed.hostname, parsed.port, context=ctx, timeout=120)
    return http.client.HTTPConnection(parsed.hostname, parsed.port, timeout=120)


def detect_model(parsed, verify_tls):
    conn = make_connection(parsed, verify_tls)
    try:
        conn.request("GET", "/v1/models")
        resp = conn.getresponse()
        data = json.loads(resp.read())
        return data["data"][0]["id"]
    except Exception as exc:
        sys.exit(f"could not list models at {parsed.geturl()}: {exc}")
    finally:
        conn.close()


def build_prompt(n_words):
    words = ["alpha", "beta", "gamma", "delta", "observability", "throughput",
             "latency", "cache", "serving", "model"]
    return " ".join(words[i % len(words)] for i in range(n_words))


def stream_response(resp):
    """Read an SSE body, counting generated tokens; returns nothing on non-SSE bodies."""
    tokens = 0
    for raw in resp:
        line = raw.decode("utf-8", "replace").strip()
        if line.startswith("data:"):
            payload = line[5:].strip()
            if payload == "[DONE]":
                break
            tokens += 1
    return tokens


def worker(args, parsed, model, prompt, end_at, burst_every):
    body = json.dumps({
        "model": model,
        "prompt": prompt,
        "max_tokens": args.max_tokens,
        "temperature": 0.7,
        "stream": True,
    }).encode()
    headers = {"Content-Type": "application/json",
               # some proxies require an Authorization header; the endpoint
               # does not validate it - "unused" is a literal placeholder
               "Authorization": "Bearer unused"}
    conn = make_connection(parsed, args.verify_tls)
    last_used = 0.0
    while not STOP.is_set() and time.time() < end_at:
        if args.ramp:
            # on/off cycles: full cycle = 2 * ramp, first half loads, second half idles
            cycle = (time.time() - start_time()) % (2 * args.ramp)
            if cycle >= args.ramp:
                if STOP.wait(min(2 * args.ramp - cycle, end_at - time.time())):
                    break
                continue
        if burst_every:
            # align to the next wave boundary on the shared clock, then fire;
            # a request that outlives a wave simply joins the next one
            delay = burst_every - ((time.time() - start_time()) % burst_every)
            if delay > 0 and STOP.wait(min(delay, burst_every)):
                break
        if time.time() - last_used > 10:
            # server keep-alive closes idle connections: reconnect before sending
            try:
                conn.close()
            except Exception:
                pass
            conn = make_connection(parsed, args.verify_tls)
        attempt = 0
        while True:
            t0 = time.time()
            try:
                conn.request("POST", "/v1/completions", body=body, headers=headers)
                resp = conn.getresponse()
                if resp.status != 200:
                    raise IOError(f"HTTP {resp.status}")
                tokens = stream_response(resp)
                with STATS_LOCK:
                    STATS["ok"] += 1
                    STATS["tokens"] += tokens
                    STATS["e2e"].append(time.time() - t0)
                if resp.will_close:
                    conn.close()
                    conn = make_connection(parsed, args.verify_tls)
                    last_used = time.time()
                break
            except Exception:
                attempt += 1
                try:
                    conn.close()
                except Exception:
                    pass
                conn = make_connection(parsed, args.verify_tls)
                if attempt >= 2:
                    with STATS_LOCK:
                        STATS["err"] += 1
                    STOP.wait(1)
                    break
        last_used = time.time()
    try:
        conn.close()
    except Exception:
        pass


_START = time.time()


def start_time():
    return _START


def main():
    global _START
    args = parse_args()
    parsed = urlparse(args.base_url)
    if not parsed.hostname:
        sys.exit(f"--base-url must look like scheme://host:port, got: {args.base_url}")

    model = args.model or detect_model(parsed, args.verify_tls)
    prompt = build_prompt(args.prompt_words)
    end_at = time.time() + args.duration

    print(f"endpoint      : {parsed.geturl()}")
    print(f"model         : {model}")
    print(f"pattern       : concurrency={args.concurrency} duration={args.duration}s "
          f"max_tokens={args.max_tokens} prompt_words={args.prompt_words} "
          f"burst_every={args.burst_every or 0}s")
    print("ctrl-c to stop early\n")

    threads = [threading.Thread(target=worker,
                                args=(args, parsed, model, prompt, end_at, args.burst_every),
                                daemon=True)
               for _ in range(args.concurrency)]
    _START = time.time()
    for t in threads:
        t.start()

    try:
        next_report = time.time() + 15
        while any(t.is_alive() for t in threads):
            if STOP.wait(0.5):
                break
            now = time.time()
            if now >= next_report:
                with STATS_LOCK:
                    print(f"  {int(_START and now - _START):4}s  ok={STATS['ok']:5}  "
                          f"err={STATS['err']:3}  tokens={STATS['tokens']}")
                next_report = now + 15
    except KeyboardInterrupt:
        print("\nstopping early...")
        STOP.set()

    for t in threads:
        t.join(timeout=30)

    e2e = sorted(STATS["e2e"])
    if e2e:
        p50 = e2e[len(e2e) // 2]
        p90 = e2e[int(len(e2e) * 0.9)]
    else:
        p50 = p90 = 0.0
    print(f"\ndone: ok={STATS['ok']}  err={STATS['err']}  tokens={STATS['tokens']}  "
          f"e2e p50={p50:.2f}s  p90={p90:.2f}s")
    print("give Prometheus a scrape (~30s), then check the dashboard panels.")


if __name__ == "__main__":
    main()
