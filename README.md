# OpenShift AI Community Dashboards and Observability Applications

A community-driven collection of custom dashboards as code for Red Hat OpenShift AI (RHOAI). This repository brings together contributions from field teams, customers, and the wider community to answer operational questions specific to their AI workloads and organizations.

Contributions include Perses and Grafana dashboards or entries in the [dashboard register](https://github.com/rh-aiservices-bu/rhoai-community-dashboards/tree/main/dashboards#dashboard-register) - an index of dashboards that live off-repository.

**Full documentation:** https://rh-aiservices-bu.github.io/rhoai-community-dashboards/

| Guide | What it covers |
|-------|----------------|
| [Overview](https://rh-aiservices-bu.github.io/rhoai-community-dashboards/modules/main/index.html) | What this repository is for and what it requires |
| [Custom Dashboards](https://rh-aiservices-bu.github.io/rhoai-community-dashboards/modules/main/custom-dashboards.html) | Naming and ordering conventions, Perses vs Grafana, the dashboard register |
| [Repository Structure](https://rh-aiservices-bu.github.io/rhoai-community-dashboards/modules/main/repository-structure.html) | Directory layout, the dashboard directory contract, what CI checks |
| [Deploy a Perses Dashboard](https://rh-aiservices-bu.github.io/rhoai-community-dashboards/modules/main/deploy-perses.html) | Verifying the Monitoring Stack, applying a `PersesDashboard`, troubleshooting |
| [The RHOAI Monitoring Stack](https://rh-aiservices-bu.github.io/rhoai-community-dashboards/modules/main/rhoai-monitoring.html) | What the platform deploys and where dashboard data comes from |
| [Contribution Guide](https://rh-aiservices-bu.github.io/rhoai-community-dashboards/modules/main/contributing.html) | Scope, workflow, the README each dashboard needs, review gates |

## What is a custom dashboard?

A custom dashboard extends or reorganizes the views provided out of the box by OpenShift AI, by querying underlying observability data.

Examples of contributions we welcome:

| Example | What it helps you understand |
| --- | --- |
| **Extended vLLM diagnostics** | Add metrics beyond the built-in Perses dashboard, to assist with investigating throughput or latency changes. |
| **Usage attribution and showback** | Use available RHOAI Models-as-a-Service usage data, such as token consumption and request counts, with subscription-to-team mappings and organization-defined rates to estimate costs by team or cost center. |
| **Organization-wide AI operations overview** | Combine vLLM performance, llm-d serving health, infrastructure and GPU health, and usage into a single view organized around the models, projects, or services an organization operates. |
| **GPU capacity and efficiency** | Combine GPU utilization and memory metrics with serving demand and workload placement to identify idle capacity, resource pressure, and opportunities to adjust model deployment sizes. |
| **Inference service objectives** | Track latency targets, request success rates, and throughput by model or service. Where available, link to traces and logs to investigate periods when service targets are missed. |

## Observability data sources

Dashboards and applications should build on telemetry from OpenShift AI workloads and the OpenShift platform supporting them:

- **Prometheus for metrics:** the primary source for model serving, platform health, and available usage metrics. OpenShift platform metrics may also be accessed through Thanos, depending on the environment.
- **Tempo for distributed traces:** use when tracing and workload instrumentation are enabled.
- **Loki for logs, when separately configured:** an optional source for environments with a logging stack. Do not assume Loki is installed by OpenShift AI.

The documented [OpenShift AI observability stack](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/managing_openshift_ai/managing-observability_managing-rhoai) uses Prometheus and Tempo, with OpenTelemetry for collection. [MaaS observability](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/govern_llm_access_with_models-as-a-service/index) describes usage tracking and showback inputs. Consult the documentation for your installed release.

Applications may also consume usage events or component APIs and combine them with business data such as pricing and team mappings. Each contribution must identify its actual data sources, required metrics, events, or trace attributes, collection prerequisites, and access requirements. Dashboard filters do not replace backend authorization or tenant isolation.

## Dashboard formats

- **Perses:** dashboard definitions in JSON or YAML, including `PersesDashboard` Kubernetes resources where appropriate. Specify whether a file is a native Perses resource or an operator custom resource and explain how to deploy it. See the [Perses CLI documentation](https://perses.dev/perses/docs/cli/).
- **Grafana:** dashboard JSON, optionally accompanied by YAML provisioning configuration or an operator resource with deployment instructions. See [Grafana provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/#dashboards).

Dashboard contributions can target either tool. Equivalent versions for both are welcome but are not required. Document the tested dashboard tool version and any required plugins; the formats are not interchangeable.

## Dashboard Register

The [dashboard register](https://github.com/rh-aiservices-bu/rhoai-community-dashboards/tree/main/dashboards#dashboard-register) is an index of dashboards that live in their own repositories rather than in this tree. 

Some dashboards ship as part of a larger application, where the dashboard and the exporter that feeds it are versioned together and would drift if copied here. This register points to those, so they can be found alongside the dashboards held directly in this repository.

## Contributing

Submit a pull request containing the dashboard files or application source code and a short README with:

- Purpose, intended audience, and an optional screenshot using sanitized data.
- Maintainer or owner.
- Tested OpenShift AI, runtime, and applicable dashboard tool or application dependency versions.
- Required data sources, metric names, labels, units, and any recording rules or additional exporters.
- Import or deployment instructions, variables to configure, and known limitations.
- Any attribution mappings or cost assumptions used for showback.

Remove credentials, customer identifiers, internal endpoints, and sensitive data before contributing. Parameterize environment-specific values where possible.

Full contribution guidelines can be found in our [Contribution Guide](https://rh-aiservices-bu.github.io/rhoai-community-dashboards/modules/main/contributing.html)

## Support

Dashboards and applications in this repository are community contributions, not Red Hat supported product content. Validate compatibility, queries, application behavior, and data access controls before deployment. 

If you notice any problems, please raise an issue!

