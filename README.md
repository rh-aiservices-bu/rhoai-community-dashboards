# OpenShift AI Community Dashboards and Observability Applications

A community-driven collection of custom dashboards as code and observability application code for Red Hat OpenShift AI (RHOAI). This repository brings together contributions from field teams, customers, and the wider community to answer operational questions specific to their AI workloads and organizations.

Keep dashboard definitions and application source code in Git, adapt them to your environment, and deploy them through the documented installation or GitOps workflow. Contributions can include Perses and Grafana dashboards, services, operators, and user interfaces that turn OpenShift AI telemetry and usage data into operational insights and workflows.

**Full documentation:** https://rh-aiservices-bu.github.io/rhoai-dashboards-as-code/

| Guide | What it covers |
|-------|----------------|
| [Overview](https://rh-aiservices-bu.github.io/rhoai-dashboards-as-code/modules/main/index.html) | What this repository is for and what it requires |
| [Custom Dashboards](https://rh-aiservices-bu.github.io/rhoai-dashboards-as-code/modules/main/custom-dashboards.html) | Naming and ordering conventions, Perses vs Grafana, the dashboard register |
| [Repository Structure](https://rh-aiservices-bu.github.io/rhoai-dashboards-as-code/modules/main/repository-structure.html) | Directory layout, the dashboard directory contract, what CI checks |
| [Deploy a Perses Dashboard](https://rh-aiservices-bu.github.io/rhoai-dashboards-as-code/modules/main/deploy-perses.html) | Verifying the Monitoring Stack, applying a `PersesDashboard`, troubleshooting |
| [Contribution Guide](https://rh-aiservices-bu.github.io/rhoai-dashboards-as-code/modules/main/contributing.html) | Scope, workflow, the README each dashboard needs, review gates |

## What is a custom dashboard?

A custom dashboard extends or reorganizes the views provided out of the box by OpenShift AI. It can expose additional runtime metrics, apply organization-specific filters and calculations, or bring signals from several domains into one view. It queries the underlying observability data rather than querying other dashboards.

Examples of contributions we welcome:

| Example | What it helps you understand |
| --- | --- |
| **Extended vLLM diagnostics** | Add metrics beyond the built-in Perses dashboard, such as request queuing, KV cache utilization, prefix cache behavior, and latency distributions, where exposed by the deployed vLLM version. Use these to investigate throughput or latency changes. |
| **Usage attribution and showback** | Use available RHOAI Models-as-a-Service usage data, such as token consumption and request counts, with subscription-to-team mappings and organization-defined rates to estimate costs by team or cost center. Document attribution, pricing, and calculation assumptions; usage metrics alone are not a billing system. |
| **Organization-wide AI operations overview** | Combine vLLM performance, llm-d serving health, infrastructure and GPU health, and usage into a single view organized around the models, projects, or services an organization operates. |
| **GPU capacity and efficiency** | Combine GPU utilization and memory metrics with serving demand and workload placement to identify idle capacity, resource pressure, and opportunities to adjust model deployment sizes. Requires the relevant GPU and cluster exporters. |
| **Inference service objectives** | Track latency targets, request success rates, and throughput by model or service. Where available, link to traces and logs to investigate periods when service targets are missed. |

These are example use cases, not a list of dashboards already included in this repository. Available metrics, labels, and integrations depend on the deployed versions and configuration.

## Custom observability applications

This repository also welcomes application source code that builds on OpenShift AI observability and usage data. Applications can combine telemetry with business context, maintain state, expose APIs, provide custom user interfaces, or automate operational workflows beyond what a dashboard definition provides.

Examples include:

- **Metering, showback, and billing applications:** attribute usage to teams or tenants, apply pricing rules, and provide cost reports or budget workflows.
- **Operational analysis and reporting services:** correlate metrics, traces, and logs to produce workload summaries, capacity reports, or diagnostic views.
- **Custom observability consoles and operators:** provide organization-specific interfaces or manage the lifecycle of telemetry-driven applications and their configuration.

Application contributions should include source code, dependency declarations, deployment configuration, and instructions for building, testing, running, and removing the application. Document any persistent state, external services, permissions, and actions that affect workloads or tenants.

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

## Contributing

Submit a pull request containing the dashboard files or application source code and a short README with:

- Purpose, intended audience, and an optional screenshot using sanitized data.
- Maintainer or owner.
- Tested OpenShift AI, runtime, and applicable dashboard tool or application dependency versions.
- Required data sources, metric names, labels, units, and any recording rules or additional exporters.
- Import or deployment instructions, variables to configure, and known limitations.
- For applications, build and test commands, architecture, required permissions, state storage, external integrations, and uninstall instructions.
- Any attribution mappings or cost assumptions used for showback.

Remove credentials, customer identifiers, internal endpoints, and sensitive data before contributing. Parameterize environment-specific values where possible.

## Support

Dashboards and applications in this repository are community contributions, not Red Hat supported product content. Validate compatibility, queries, application behavior, and data access controls before deployment. Installation requirements and lifecycle behavior are specific to each contribution and must be documented in its README.

