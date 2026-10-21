---
name: deploy-dashboard
description: Use when a contributor wants to deploy, apply, test, or troubleshoot a dashboard from this repository on an OpenShift cluster, or asks why a dashboard's panels are empty. Runs the pre-flight Monitoring Stack checks, applies the manifest, confirms the operator reconciled it, and works through the empty-panel troubleshooting tree.
---

# Deploy a dashboard

Reference: `content/modules/ROOT/pages/deploy-perses.adoc`. Re-read it if this file and the repo
disagree.

Almost everything that goes wrong here goes wrong before `oc apply`: in the namespace chosen, or
in the datasource the dashboard references. Front-load the checks.

## 1. Pre-flight: verify the Monitoring Stack

Run the automated check before applying anything:

```bash
./validation/scripts/validate_monitoring.sh
```

Needs `oc`, logged in to the target cluster. It checks, in order: the `DSCInitialization` has
`spec.monitoring.managementState: Managed` and `status.phase: Ready`; the `DataScienceCluster` has
`ComponentsReady: True`; the monitoring namespace and its Alertmanager/Prometheus/OTel
Collector/Tempo/Thanos Querier pods are running; the Cluster Observability Operator CSV has
`Succeeded` in `openshift-cluster-observability-operator` specifically (not
`openshift-operators` — the RHOAI `perses-operator-access` `NetworkPolicy` only admits that
namespace, and installing COO elsewhere breaks the Perses path with no error until dashboard
apply); the `MonitoringStack`, `TempoMonolithic`, and `OpenTelemetryCollector` child objects are
ready; and that both `PersesDatasource` CRs exist with `Available: True`, `Degraded: False`.

It validates only — it never installs anything. If it reports any failures, stop and fix those
first: a dashboard referencing a datasource that doesn't exist applies cleanly and renders every
panel empty, which is a far more confusing failure than an apply error. The manual checks in
`deploy-perses.adoc` ("Manual Verification of the Monitoring Stack") cover the same ground if you
need to dig into a specific failure by hand.

## 2. Apply it

```bash
oc apply -f dashboards/<dashboard-name>/perses/
```

For a Grafana dashboard, apply the `GrafanaDashboard` CR specifically, not the whole directory —
`grafana/` also holds the raw dashboard JSON (`<slug>.json`), which isn't a standalone Kubernetes
resource and isn't something `oc apply` can use on its own:

```bash
oc apply -f dashboards/<dashboard-name>/grafana/<slug>-cr.yaml
```

Caveat: there's no `deploy-grafana.adoc` yet, so this isn't confirmed against a worked example in
this repo the way the Perses path is — revisit this step once one exists.

Namespace is not optional: `PersesDatasource` is project-scoped, so the manifest's
`metadata.namespace` must be `redhat-ods-monitoring`, the namespace holding the datasource — not
`default`, not wherever `oc apply` happens to default to.

## 3. Confirm the resource exists

```bash
oc get persesdashboards -n redhat-ods-monitoring
```

## 4. Confirm the operator actually reconciled it

The dashboard is only real once `perses-operator` has pushed it to the Perses server — a malformed
spec surfaces here, not at apply time:

```bash
oc logs -n openshift-cluster-observability-operator \
  -l app.kubernetes.io/name=perses-operator --tail=50 | grep -i dashboard
```

Healthy output looks like:

```
info Reconciling PersesDashboard: redhat-ods-monitoring/dashboard-99-<slug>
info Dashboard updated: dashboard-99-<slug>
```

Then open **Observe -> Observability** in the OpenShift AI console. The dashboard appears as a tab
after the built-in ones, titled with the `[C] -` prefix.

## 5. If panels are empty

The manifest is valid and reconciling — what's left is the data path. Check in this order:

1. **Datasource in the wrong namespace.** `oc get persesdatasources -n <dashboard-namespace>`
   returns nothing -> move the dashboard to `redhat-ods-monitoring`.
2. **Metric doesn't exist on this cluster.** Query it directly under *Observe -> Metrics* with no
   label filter. Runtime metric names (vLLM especially) move between versions and a renamed metric
   just returns nothing, with no error.
3. **The variable matched nothing.** An empty dropdown means the `matchers` on the `ListVariable`
   selected a metric with no series; the panel query then filters on an empty variable.
4. **A label was renamed.** Compare against a built-in dashboard's query for the same data —
   label names and `_total` suffixes have moved between RHOAI releases.

## 6. Remove it

```bash
oc delete -f dashboards/<dashboard-name>/perses/
```

Each dashboard is an independent resource; deleting one doesn't affect any other.
