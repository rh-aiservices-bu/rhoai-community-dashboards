## Platform Billing Overview

Repository: [rdwj/platform-billing-operator](https://github.com/rdwj/platform-billing-operator)

Provider-side view of a Models-as-a-Service billing deployment, covering revenue, rating
throughput, tenant state, and budget consumption in one place. Intended for the platform team
operating the service rather than for tenants.

Ten panels: monthly recurring revenue, events rated, payment failure rate, tenant state
distribution, revenue per tenant over 24 hours, usage volume by ingest result, drift status,
budget utilization, churn risk, and tenant balance. Templated on `tenant_id`, defaulting to a
24 hour window with a 30 second refresh.

Instrumented metrics come from the operator's controller-manager metrics endpoint:
`billing_tenant_balance`, `billing_tenant_state`, `billing_budget_utilization`,
`billing_events_rated_total`, `billing_ingest_total`, `billing_drift_pct`, and
`billing_drift_exceeded`.

Four panels read recording rules rather than raw series: `billing:mrr:sum`,
`billing:payment_failure:rate`, `billing:revenue_per_tenant:sum`, and `billing:churn_risk:ratio
`.
These ship with the operator as a `PrometheusRule` in `config/prometheus/rules.yaml`. The
dashboard renders empty panels without them, so apply that resource before importing.

The operator is pre-1.0 and its metric names are not yet stable. Pin to a tagged release when
one is available rather than tracking `main`.
