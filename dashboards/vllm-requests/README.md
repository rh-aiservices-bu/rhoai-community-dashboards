# vLLM Requests

Running request count per vLLM model. Deliberately minimal: it exists as the
worked example that the documentation and the structural validator are both
built around, so it is the smallest thing that satisfies the contract.

If you are adding a dashboard, copy this directory as the starting shape.

| | |
|---|---|
| **Purpose** | Show how many requests each vLLM model currently has in flight, as a first look before reaching for a deeper performance dashboard. |
| **Audience** | Anyone operating model serving on this cluster. No admin rights needed. |
| **Maintainer** | [@rcarrata](https://github.com/rcarrata) |
| **Format** | Perses, `perses.dev/v1alpha2` |

## Tested against

| Component | Version |
|---|---|
| OpenShift AI | 3.5 |
| Perses CRDs | via Cluster Observability Operator, `perses.dev/v1alpha2` |
| vLLM | metric name verified on the serving runtime in use; see limitations |

## Required data

| | |
|---|---|
| **Datasource** | `data-science-prometheus-datasource`, the one supplied by the RHOAI Monitoring Stack. Nothing extra to deploy. |
| **Metric** | `vllm:num_requests_running`, exported by vLLM model servers |
| **Label** | `model_name`, used both to group the series and to populate the `model` variable |

The `model` dropdown is built from label values on that metric, so it lists
only models currently exporting it rather than every `model_name` ever scraped.

## Deploy

```bash
oc apply -f dashboards/vllm-requests/perses/
```

The namespace is set in the manifest and matters: `PersesDatasource` is
project-scoped, so a dashboard outside `redhat-ods-monitoring` applies cleanly
and then renders empty with no error anywhere. See
[Deploy a Perses Dashboard](https://rh-aiservices-bu.github.io/rhoai-dashboards-as-code/modules/main/deploy-perses.html).

Remove it with:

```bash
oc delete -f dashboards/vllm-requests/perses/
```

## Known limitations

- **One panel.** This is an example, not a diagnostic tool. For queueing, KV
  cache behaviour or latency distributions you want a fuller vLLM dashboard.
- **vLLM metric names move between runtime versions.** If the panel is empty,
  query `vllm:num_requests_running` directly under *Observe -> Metrics* with no
  label filter before assuming the dashboard is at fault.
- **No Grafana equivalent.** Not required, and not planned here.
