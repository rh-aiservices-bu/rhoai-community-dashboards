# Dashboard register

An index of dashboards that live in their own repositories rather than in this tree.

Some dashboards ship as part of a larger application, where the dashboard and the exporter that
feeds it are versioned together and would drift if copied here. This register points to those,
so they can be found alongside the dashboards held directly in this repository.

Contribution requirements are in the [root README](../README.md). Entries here are expected to
meet the same bar: no credentials, no customer identifiers, no internal endpoints, and the
required metrics documented.

See [Dashboard Register](https://rh-aiservices-bu.github.io/rhoai-community-dashboards/modules/main/dashboard-register.html) in the full documentation for more information.

## Register

| Dashboard | Source repository | Format | Required data | Maintainer |
| --- | --- | --- | --- | --- |
| [Platform Billing Overview](./platform-billing-operator.md) | [rdwj/platform-billing-operator](https://github.com/rdwj/platform-billing-operator) ([dashboard JSON](https://github.com/rdwj/platform-billing-operator/blob/main/config/grafana/billing-overview.json)) | Grafana, schemaVersion 39 | Prometheus; `billing_*` metrics and four recording rules exported by the operator | [@rdwj](https://github.com/rdwj) |
