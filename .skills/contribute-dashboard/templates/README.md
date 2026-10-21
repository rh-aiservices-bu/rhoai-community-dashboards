# <Dashboard Title>

<One or two sentences: what question this dashboard answers.>

| | |
|---|---|
| **Purpose** | <What it's for.> |
| **Audience** | <Who it's for, and what access they need, if any.> |
| **Maintainer** | [@<github-handle>](https://github.com/<github-handle>) |
| **Format** | Perses, `perses.dev/v1alpha2` <and/or Grafana, schemaVersion N> |

## Tested against

| Component | Version |
|---|---|
| OpenShift AI | <e.g. 3.5> |
| Perses CRDs | via Cluster Observability Operator, `perses.dev/v1alpha2` |
| <runtime, e.g. vLLM> | <specific version — "recent" is not a version> |

## Required data

| | |
|---|---|
| **Datasource** | `data-science-prometheus-datasource` or `cluster-prometheus-datasource`, supplied by the RHOAI Monitoring Stack. Nothing extra to deploy, unless noted. |
| **Metric(s)** | `<metric_name>`, exported by `<component>` |
| **Label(s)** | `<label>`, used for `<what>` |

## Deploy

```bash
oc apply -f dashboards/<slug>/perses/
```

<Note anything beyond the Monitoring Stack, e.g. required recording rules or operators.>

Remove it with:

```bash
oc delete -f dashboards/<slug>/perses/
```

## Known limitations

- <Panels that need a metric not everyone has, assumptions about model naming, etc.>
