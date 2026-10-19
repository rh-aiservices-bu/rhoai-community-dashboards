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
