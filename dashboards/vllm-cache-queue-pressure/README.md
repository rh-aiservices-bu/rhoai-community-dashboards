# vLLM Cache & Queue Pressure

## Purpose and audience

Explains the engine-side causes of vLLM latency degradation that the built-in
Perses dashboards cannot show: KV cache saturation, queue depth, inter-token
latency stalls, and where engine time goes (prefill vs decode), per model.
Intended for platform administrators and AI observability teams investigating
why TTFT or end-to-end latency changed.

## What questions it answers

| Question | Panel | Action it informs |
|---|---|---|
| Latency spiked - was the engine saturated, or is something else wrong? | KV cache utilization % | Cache pinned near 100% -> add capacity or raise `gpu_memory_utilization`; cache fine -> look elsewhere |
| Why are requests queueing when traffic has not grown? | Waiting requests next to KV cache utilization | Cache pressure fills the queue even at flat volume: fix context length or config, not replicas |
| Is the engine struggling between tokens even though nothing failed? | Inter-token latency p90 (s) | Spikes reveal cache thrash, preemption recompute, or GPU contention - none of which produce failed requests |
| Where does the engine's time go? | Prefill vs decode time p90 (s) | Rising prefill = longer prompts or cold cache; rising decode = long generations or memory pressure |
| Was the latency change driven by traffic, or by the engine? | Token throughput (tokens/s) | Throughput and latency move together -> demand-driven; flat throughput + rising latency -> engine-side problem |
| Is this deployment sized right for its workload? | All signal panels together | Sustained pressure + queueing = right-size or add capacity; consistently low = consolidate |

The built-in dashboards show the symptom (e2e/TTFT p90 rising, requests
waiting) but not the cause. This dashboard closes that gap with the
engine-side signals.

## Maintainer

@suhasvkashyap

## Tested versions

- RHOAI 3.6.0-ea.2 with the Cluster Observability Operator (v1.5.2) monitoring
  stack; Perses server `data-science-perses`
- vLLM-based KServe serving runtime (`llm-isvc` deployments); all metric names
  verified against the live data-science Thanos Querier at contribution time
- Demo tooling (`load-generation/`) verified against `llm-d/llm-d-inference-sim`
  v0.8.2 engines
- Perses dashboard: `PersesDashboard` CR, `perses.dev/v1alpha2` (shipped COO build)

## Required metrics

All read from the out-of-the-box `data-science-prometheus-datasource`, exported
by the vLLM serving runtime and collected by the RHOAI OpenTelemetry collector:

| Metric | Type | Panel |
|---|---|---|
| `vllm:kv_cache_usage_perc` | gauge (0-1) | KV cache utilization % |
| `vllm:num_requests_waiting` | gauge | Waiting requests |
| `vllm:inter_token_latency_seconds_bucket` | histogram | Inter-token latency p90 (s) |
| `vllm:request_prefill_time_seconds_bucket` | histogram | Prefill vs decode time p90 (s) |
| `vllm:request_decode_time_seconds_bucket` | histogram | Prefill vs decode time p90 (s) |
| `vllm:generation_tokens_total` | counter (use `rate()`) | Token throughput (tokens/s) |
| `vllm:num_requests_running` | gauge | Model dropdown |

All metrics carry the `model_name` label, which the `model` ListVariable uses.

## Deployment

Prerequisites (checked before applying):

    oc get csv -n openshift-cluster-observability-operator \
      -o custom-columns=NAME:.metadata.name,PHASE:.status.phase   # cluster-observability-operator: Succeeded
    oc get perses,persesdatasources -n redhat-ods-monitoring      # data-science-perses + data-science-prometheus-datasource

Deploy:

    oc apply -f dashboards/vllm-cache-queue-pressure/perses/

Confirm the perses-operator pushed it to the Perses server (a malformed spec
surfaces here, not at apply time):

    oc logs -n openshift-cluster-observability-operator \
      -l app.kubernetes.io/name=perses-operator --tail=50 | grep -i dashboard

Then open Observe -> Observability in the RHOAI console: the tab appears after
the built-in dashboards, named "[C] - vLLM Cache & Queue Pressure".

Remove:

    oc delete -f dashboards/vllm-cache-queue-pressure/perses/

The manifest sets `namespace: redhat-ods-monitoring` itself (the namespace that
holds the datasource). Requires only the RHOAI Monitoring Stack - no extra
exporters, recording rules, or operators.

## Generating load (demo)

The dashboard needs live traffic to be meaningful. `load-generation/` ships a
stdlib-only generator that sends streaming OpenAI-compatible completion
requests to any vLLM or llm-d inference-sim endpoint - no tokens required, the
base URL is the only input.

Prerequisites:

    oc login --token=<token> --server=<api-url>   # values from your cluster's console login page
    oc project <model-namespace>                  # namespace holding the model

Run in-cluster (recommended - no port-forward, no local TLS setup):

    oc apply -f dashboards/vllm-cache-queue-pressure/load-generation/vllm-load-gen-pod.yaml -n <model-namespace>
    oc logs -n <model-namespace> vllm-load-gen -f

Before applying, edit the Pod's `--base-url` arg and replace
`<model-service>.<model-namespace>` with your model's in-cluster service
(also update the same URL in the ConfigMap's embedded script banner, or just
regenerate the ConfigMap - see below). The pod stops when the run finishes
(`restartPolicy: Never`), but the Pod object remains - delete it before
re-applying for another run:

    oc delete pod vllm-load-gen -n <model-namespace>

Or from your laptop:

    oc -n <model-namespace> port-forward svc/<model-service> 18000:8000
    python3 dashboards/vllm-cache-queue-pressure/load-generation/vllm-load-gen.py \
      --base-url https://localhost:18000 --concurrency 16 --ramp 120

The Pod manifest embeds a copy of the script in its ConfigMap. After editing
`vllm-load-gen.py`, regenerate the manifest so the two stay in sync - from the
repo root:

    python3 -c "
    import yaml
    docs = list(yaml.safe_load_all(open('dashboards/vllm-cache-queue-pressure/load-generation/vllm-load-gen-pod.yaml')))
    cm = next(d for d in docs if d['kind'] == 'ConfigMap')
    cm['data']['gen.py'] = open('dashboards/vllm-cache-queue-pressure/load-generation/vllm-load-gen.py').read()
    yaml.safe_dump_all(docs, open('dashboards/vllm-cache-queue-pressure/load-generation/vllm-load-gen-pod.yaml', 'w'), sort_keys=False)"

Flags that matter for the demo:

- `--ramp N` alternates N seconds of load with N seconds idle - makes the
  rate() panels rise and fall over time (the demo "mountains").
- `--concurrency 16` is a good default against a simulator with
  `--max-num-seqs 8`; much higher values pile up 60s+ queue times and errors.
- `--verify-tls` if the endpoint has a real certificate (self-signed sim certs
  are skipped by default).

Give Prometheus a scrape (~30s), set the dashboard's time range to a recent
window (e.g. Last 30m), and the panels fill in.

## Appendix: configuring the llm-d sample simulators (optional)

Out of the box the llm-d inference simulator reports constant latencies, no
queueing, and zero KV-cache usage, so only the counter-based panels move under
load. The simulator (v0.8.2) has physics knobs that make the queue and
percentile panels track load. Apply to both engine workloads for a two-model
demo:

    --prefill-overhead 100ms
    --prefill-time-per-token 2ms
    --prefill-time-std-dev 0.5ms
    --inter-token-latency 15ms
    --inter-token-latency-std-dev 4ms
    --time-factor-under-load 3     # latency scales x3 at max-num-seqs concurrency
    --max-num-seqs 8               # requests beyond this wait in the queue
    --enable-kvcache
    --kv-cache-size 512
    --block-size 16

The simulators are `LLMInferenceService` workloads, so the flags go in the CR,
not the Deployment (direct Deployment edits are reverted by the controller):

    oc patch llminferenceservice <name> -n <model-namespace> --type=json -p \
      '[{"op":"replace","path":"/spec/template/containers/0/args","value":[
           "--port","8000","--model","<model>","--mode","random","--no-mm-encoder-only",
           "--ssl-certfile","/var/run/kserve/tls/tls.crt","--ssl-keyfile","/var/run/kserve/tls/tls.key",
           "--prefill-overhead","100ms","--prefill-time-per-token","2ms","--prefill-time-std-dev","0.5ms",
           "--inter-token-latency","15ms","--inter-token-latency-std-dev","4ms",
           "--time-factor-under-load","3","--max-num-seqs","8",
           "--enable-kvcache","--kv-cache-size","512","--block-size","16"]}]'

Patch the `args` path only, with a JSON patch. A merge patch
(`--type=merge`) on `spec.template.containers` replaces the whole container
object and silently drops its `image`, `command`, `ports`, and `env` - the
controller then substitutes the default serving runtime and the pods crash.

Caveats learned the hard way:

- Standard-deviation caps: `--prefill-time-std-dev` may not exceed 30% of
  `--prefill-time-per-token`, and `--inter-token-latency-std-dev` 30% of
  `--inter-token-latency`. The sim exits at config read if violated.
- After the pods roll, their new pod IPs are not in the serving certificate's
  SAN list yet (the cert regenerates shortly after pod start, but the sim
  loads it at startup), so the OpenTelemetry collector's scrapes fail TLS
  verification. Setting `insecureSkipVerify: true` on the engine's PodMonitor
  restores scraping immediately (certs are self-signed; traffic stays
  encrypted):

      oc patch podmonitor <engine-podmonitor> -n <model-namespace> --type=json -p \
        '[{"op":"replace","path":"/spec/podMetricsEndpoints/0/tlsConfig/insecureSkipVerify","value":true}]'

  Security impact, stated plainly: this disables certificate validation. The
  collector normally authenticates the engine by its certificate; with the
  check off, anyone positioned to intercept scrape traffic can inject metric
  data, because encrypted traffic alone does not authenticate the peer. That
  is an acceptable trade for the simulator demo - the certs are self-signed
  and the scraped data is synthetic - but restore `insecureSkipVerify: false`
  after demoing, and never use it with a real engine or in production.

- If the target allocator dropped the engine's scrape jobs entirely (symptom:
  `vllm:*` metrics vanish from the Thanos Querier after a pod restart; check
  `oc logs -n redhat-ods-monitoring \
     -l app.kubernetes.io/component=opentelemetry-targetallocator | grep -i skipping`),
  the collector's service account lacks RBAC to read the TLS secret. Grant it,
  then restart the target allocator pods so the watcher re-runs:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: data-science-collector-secrets-reader
  namespace: <model-namespace>
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: data-science-collector-secrets-reader
  namespace: <model-namespace>
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: data-science-collector-secrets-reader
subjects:
  - kind: ServiceAccount
    name: data-science-collector-collector
    namespace: redhat-ods-monitoring
```

The verbs are `get`, `list`, and `watch`, not `get` alone: the target
allocator runs a list-and-watch informer over Secrets so it picks up secret
rotation, and a `get`-only role stops that watcher from ever syncing
(`failed to list secrets ... cannot list resource` in its logs, and the
engine's scrape jobs never appear). The access is namespace-scoped - nothing
cluster-wide.

What moves with these knobs, and what does not: prefill/ITL/decode p90 and
waiting requests rise and fall with load; the sim's percentile values are
quantized to fixed histogram buckets, so lines step rather than curve; the
KV-cache gauge stays flat on this simulator build - that panel needs a real
vLLM engine.

Revert by re-patching the CR args back to the originals, setting
`insecureSkipVerify` back to `false`, and deleting the Role/RoleBinding:

    oc delete role data-science-collector-secrets-reader -n <model-namespace>
    oc delete rolebinding data-science-collector-secrets-reader -n <model-namespace>
    oc delete role data-science-collector-secrets-reader -n redhat-ods-monitoring
    oc delete rolebinding data-science-collector-secrets-reader -n redhat-ods-monitoring

## Known limitations

- The vLLM build shipped with RHOAI 3.6 EA does not emit
  `vllm:prefix_cache_hits/queries`, `vllm:num_preemptions_total`, or
  `vllm:request_queue_time_seconds`, so prefix-cache effectiveness and
  preemption counts cannot be charted here yet. Upstream vLLM emits these; on a
  newer engine build, add panels with:

      100 * (sum by (model_name) (rate(vllm:prefix_cache_hits_total{model_name=~"$model"}[$__rate_interval]))
            / clamp_min(sum by (model_name) (rate(vllm:prefix_cache_queries_total{model_name=~"$model"}[$__rate_interval])), 1e-10))
      sum by (model_name) (rate(vllm:num_preemptions_total{model_name=~"$model"}[$__rate_interval]))

- vLLM metric names vary between releases (counter suffixes have moved across
  versions). If a panel renders empty, list the engine's actual names with
  `{__name__=~"vllm:.*"}` in Observe -> Metrics and adjust.
- KV cache utilization shows the worst replica per model (max), not the average.

## Screenshot

To be added before review (sanitized data only).
