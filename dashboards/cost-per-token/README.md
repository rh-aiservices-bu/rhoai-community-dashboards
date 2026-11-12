# Cost per Token

Compares the token mix your vLLM deployments actually serve against the list
price of equivalent usage on commercial APIs, plus the amortized hardware cost
of running the same load yourself.

| | |
|---|---|
| **Purpose** | Price the same workload three ways: fresh vs cached prompt tokens on hardware, the equivalent bill on selected API models, and the hardware cost over the selected window. |
| **Audience** | Cluster operators and platform teams comparing self-hosted serving costs with API pricing. Requires `cluster-monitoring-view` to see data (the dashboard name ends in `-admin`). |
| **Maintainer** | [@jharmison-redhat](https://github.com/jharmison-redhat) |
| **Format** | Perses, `perses.dev/v1alpha2` |

## Tested against

| Component | Version |
|---|---|
| OpenShift AI | 3.5 |
| Perses CRDs | via Cluster Observability Operator, `perses.dev/v1alpha2` |
| vLLM | bundled with the RHOAI 3.5 stack |
| OpenShift | 4.22 |

## Required data

| | |
|---|---|
| **Datasource** | `cluster-prometheus-datasource`, supplied by the RHOAI Monitoring Stack. |
| **Metric(s)** | `kserve_vllm:prompt_tokens_total`, `kserve_vllm:prompt_tokens_cached_total`, `kserve_vllm:prompt_tokens_recomputed_total`, `kserve_vllm:generation_tokens_total`, `kserve_vllm:num_requests_running`, exported by the RHOAI/KServe monitoring stack, plus `rhai_api_pricing_mtok`, recorded by the companion `rules/pricing-rule.yaml` shipped in this directory. The API-comparison panels are empty without that rule. |
| **Label(s)** | `namespace` and `model_name` on the vLLM metrics; `pair`, `token_type`, and `context` on the pricing series. |

These metrics are collected automatically from vLLM deployments: the
KServe/RHOAI monitoring stack scrapes the vLLM engine's own metrics and
exposes them as the `kserve_vllm:*` series above, so no configuration is
needed for collection. The cached and recomputed prompt token metrics the
cost math depends on require a serving image with vLLM v0.16 or later; Red
Hat AI Inference Server 3.3.x images do not export that family, while Red
Hat AI Inference 3.4.0-ea.2 and later, including the 3.5 and 3.6
releases, do (see the [Red Hat AI Inference 3.5.0 release
notes](https://docs.redhat.com/en/documentation/red_hat_ai_inference/3.5/html/release_notes/rhaii-350-ga-release-notes_release-notes)).
Check the version badge on the model server or serving runtime in the
OpenShift AI UI to confirm which vLLM version a serving image carries.

## Deploy

```bash
oc apply -f dashboards/cost-per-token/perses/
oc apply -f dashboards/cost-per-token/rules/pricing-rule.yaml
```

The pricing rule works as shipped. `redhat-ods-monitoring` carries
`openshift.io/cluster-monitoring=true`, so the platform Prometheus evaluates
the rule there and the recorded series are visible to the central Thanos
Querier that `cluster-prometheus-datasource` queries. If your cluster prefers
user-workload evaluation, apply the rule to a UWM-scraped workload namespace
instead; UWM's `enforcedNamespaceLabel` adds a `namespace` label to every
pricing series.

Remove it with:

```bash
oc delete -f dashboards/cost-per-token/perses/
oc delete -f dashboards/cost-per-token/rules/pricing-rule.yaml
```

## Known limitations

- **Hardware cost defaults to 0.** The `HW $/yr` variable feeds arithmetic in
  the query, so it cannot ship empty: set your own annual hardware cost (plain
  number, USD per year) or the hardware-cost panels show $0.
- **No default project or model selection.** Perses auto-selects the first
  available value in each multi-select combobox when no default is set, so
  panels populate on load; explicit selections (or All) still apply normally.
- **The breakdown table is a Perses table panel.** Table panels need plugins
  beyond the out-of-the-box Perses install; the table renders on the tested
  Cluster Observability Operator build (OCP 4.22 / RHOAI 3.5), and community
  Perses builds may render it empty depending on their plugin support.
- **The `-admin` name suffix** marks the dashboard as a cluster-wide view, so
  the console hides it from users without the `cluster-monitoring-view` role.
- **API prices are snapshot list prices.** The rule header records the as-of
  date; gpt-5.6-sol pricing is promotional and noted in the rule.
- **Older serving images over-report fresh input.** Serving images with vLLM
  older than v0.16 (for example RHAIS 3.3.x-based ones) lack the cached and
  recomputed token metrics, so the Fresh-input stat counts cached and
  recomputed tokens as fresh input and the cache-read panels stay empty; the
  panels do not error. If cost numbers look too high, check the serving
  image's vLLM version via the version badge in the OpenShift AI UI. The
  `--enable-prompt-tokens-details` and `--enable-force-include-usage` flags do
  not gate these metrics: on serving images that export the family,
  deployments without either flag export it too. The flags only affect OpenAI
  API usage reporting (unconditional `usage` in streaming responses, the
  `prompt_tokens_details` breakdown) and remain optional; add them under
  Configuration parameters → Additional serving runtime arguments on RHOAI
  3.5-era runtimes.
