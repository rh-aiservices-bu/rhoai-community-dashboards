# vLLM Token Throughput

Output token rate per vLLM model.

| | |
|---|---|
| **Purpose** | Show how fast each model is producing output tokens. |
| **Audience** | Anyone operating model serving. |
| **Maintainer** | [@rcarrata](https://github.com/rcarrata) |
| **Format** | Perses, `perses.dev/v1alpha2` |

## Tested against

| Component | Version |
|---|---|
| OpenShift AI | 3.5 |
| vLLM | recent |

## Required data

| | |
|---|---|
| **Datasource** | `data-science-prometheus-datasource` |
| **Metric** | `vllm:generation_tokens_total` |

## Deploy

```bash
oc apply -f dashboards/vllm-tokens/perses/
```
