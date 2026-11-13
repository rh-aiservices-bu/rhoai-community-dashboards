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

## Dashboard Register

The [dashboard register](https://github.com/rh-aiservices-bu/rhoai-community-dashboards/tree/main/dashboards#dashboard-register) is an index of dashboards that live in their own repositories rather than in this tree. 

Some dashboards ship as part of a larger application, where the dashboard and the exporter that feeds it are versioned together and would drift if copied here. This register points to those, so they can be found alongside the dashboards held directly in this repository.

## Generating Load for Dashboards

Dashboards need live traffic to show meaningful data. [`validation/guidellm-job`](validation/guidellm-job) is a generic, reusable OpenShift `Job` that runs [GuideLLM](https://github.com/vllm-project/guidellm) against any OpenAI-compatible model endpoint to produce that traffic - useful when validating a dashboard against a real model instead of waiting for organic usage. 

It ships as a Kustomize base plus a few example overlays (chat-like traffic, long-context/summarization, and high-concurrency stress) that you can copy and point at your own endpoint.

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