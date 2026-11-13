# GuideLLM load-generation Job

An OpenShift `Job` that runs [GuideLLM](https://github.com/vllm-project/guidellm)
against an OpenAI-compatible endpoint (vLLM, llm-d, etc.) to generate traffic
so the community dashboards in `dashboards/` have live metrics to visualise.
Uses the upstream `ghcr.io/vllm-project/guidellm` image unmodified - no custom
image build required.

## Layout

```
base/                               Job + default (placeholder) config - do not edit per-run
overlays/chat-latency/              512 prompt / 200 output tokens, concurrency 8
overlays/long-context-summarization/ 4096 prompt / 300 output tokens, concurrency 4
overlays/high-concurrency-stress/   256 prompt / 128 output tokens, concurrency 64
```

Each overlay is a starting point, not a fixed menu - copy one and adjust its
`run.env` for your own workload. The token counts above are approximations of
real-world traffic patterns (chat, RAG/summarization, and a throughput stress
test respectively) backed by public benchmark data - see each overlay's
`run.env` comments for sources. **Check your target model's context window
before using `long-context-summarization`** - see the warning below.

## Configuring a run

Never edit `base/job.yaml` or any `kustomization.yaml`. All per-run values
live in each overlay's `run.env` file (plain `KEY=value` lines, one per
line), picked up by `configMapGenerator` with `behavior: merge`:

| Variable | Meaning |
|---|---|
| `BENCH_TARGET` | Base URL of the OpenAI-compatible endpoint. |
| `BENCH_MODEL` | Model name as the server expects it in requests |
| `BENCH_TOKENIZER` | Hugging Face repo id of the model actually running, for local tokenization |
| `BENCH_PROMPT_TOKENS` | Average input tokens per request |
| `BENCH_OUTPUT_TOKENS` | Average output tokens per request |
| `BENCH_CONCURRENCY` | Number of concurrent request streams |
| `BENCH_MAX_REQUESTS` | Stop after this many requests (whichever constraint hits first wins) |
| `BENCH_MAX_DURATION_SECONDS` | Stop after this many seconds |
| `BENCH_VERIFY_TLS` | `true`/`false` |

Each overlay also has a `secret.env` file for `BENCH_API_KEY`, that contains the API key to auth to the model. 

`secret.env` files are git-ignored so keys never get committed.

To add a new overlay, copy an existing one and edit its env files:

```bash
cp -r overlays/chat-latency overlays/my-run
# edit overlays/my-run/run.env and overlays/my-run/secret.env
```

## Running

> **Note:** Every overlay ships with placeholder (`change-me`) values in `run.env` - fill
those in for your model before applying, then:

```bash
oc project <model-namespace>
oc apply -k validation/guidellm-job/overlays/chat-latency
oc logs -f job/guidellm-run
```

Nothing deletes the Job/pod automatically, so `oc logs job/guidellm-run` keeps
working after the run finishes too.

Delete before re-running (Jobs don't update in place):

```bash
oc delete job guidellm-run
```

## Notes

- The dashboards read live metrics from the vLLM engine via Prometheus, not from GuideLLM's own report - this Job doesn't need to produce anything for them to work. GuideLLM's full JSON report is still printed to stdout at the end of the run (after the human-readable summary) purely for anyone who wants to inspect the raw numbers.
- **Check the target model's context window before running `long-context-summarization`** (4096 prompt + 300 output tokens by default). Many small open-weight models cap out at 4096 or 8192 total tokens, and `BENCH_PROMPT_TOKENS + BENCH_OUTPUT_TOKENS` must stay under that or requests will fail or get truncated. Find the real limit with:

  ```bash
  curl -ks <target>/v1/models | jq '.data[].max_model_len'
  ```

  then lower `BENCH_PROMPT_TOKENS` in `run.env` to comfortably fit, leaving room for `BENCH_OUTPUT_TOKENS`.
