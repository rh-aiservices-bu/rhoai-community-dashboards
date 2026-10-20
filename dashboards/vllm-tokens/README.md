# vLLM Token Throughput

Output token rate per vLLM model, as tokens per second rather than a running
total.

| | |
|---|---|
| **Purpose** | Show how fast each model is producing output tokens, to spot a model that has slowed down or stopped serving. |
| **Audience** | Anyone operating model serving on this cluster. No admin rights needed. |
| **Maintainer** | [@rcarrata](https://github.com/rcarrata) |
| **Format** | Perses, `perses.dev/v1alpha2` |

## Tested against

| Component | Version |
|---|---|
| OpenShift AI | 3.5 |
| Perses CRDs | via Cluster Observability Operator, `perses.dev/v1alpha2` |
| vLLM | 0.8.x |

## Required data

| | |
|---|---|
| **Datasource** | `data-science-prometheus-datasource`, supplied by the RHOAI Monitoring Stack. Nothing extra to deploy. |
| **Metric** | `vllm:generation_tokens_total`, a counter exported by vLLM model servers |
| **Label** | `model_name`, used to group the series and to populate the `model` variable |

The query applies `rate()` over a 5 minute window and aggregates with
`sum by (model_name)`, so each selected model keeps its own series.

## Deploy

```bash
oc apply -f dashboards/vllm-tokens/perses/
```

The namespace in the manifest matters: `PersesDatasource` is project-scoped, so
a dashboard outside `redhat-ods-monitoring` applies cleanly and then renders
empty with no error anywhere.

Remove it with:

```bash
oc delete -f dashboards/vllm-tokens/perses/
```

## Known limitations

- **One panel.** Throughput only. It will not tell you why throughput dropped,
  so pair it with a latency or queueing dashboard.
- **The 5 minute window smooths short spikes.** A burst shorter than that shows
  up lower than it really was.
- **vLLM metric names move between runtime versions.** If the panel is empty,
  query `vllm:generation_tokens_total` directly under *Observe -> Metrics* with
  no label filter before assuming the dashboard is wrong.
- **No Grafana equivalent.** Not required, and not planned.
