---
name: contribute-dashboard
description: Use when a contributor wants to add a new Perses or Grafana dashboard to this repository, or asks "how do I contribute a dashboard" / "add a dashboard for X". Scaffolds the dashboard directory, README, and manifest to the repo's naming and structural conventions, then runs the CI validator before the contributor opens a pull request.
---

# Contribute a dashboard

Reference: `content/modules/ROOT/pages/contributing.adoc`, `repository-structure.adoc`, and
`custom-dashboards.adoc`. Re-read those if this file and the repo disagree — the docs are the
source of truth, not this skill.

## 1. Check it belongs in this repository at all

Ask one question: does the dashboard query only `data-science-prometheus-datasource` or
`cluster-prometheus-datasource`?

- **Yes** -> continue below.
- **No** (own exporter/operator, joins multiple datasources, ships versioned with an application,
  or maintains its own state/API) -> it belongs in the
  [dashboard register](../../dashboards/README.md) instead, as a row in `dashboards/README.md`,
  not a directory here. Stop and help the contributor write that row instead.

## 2. Gather the facts up front

Ask for whatever isn't already given:

- Dashboard name/subject (used to derive the lowercase-hyphenated slug, e.g. `gpu-utilization`).
- Format(s): Perses, Grafana, or both.
- Purpose and audience (one or two sentences each).
- Maintainer (GitHub handle or team).
- Required metrics and the component that exports them.
- OpenShift AI version tested, and runtime version if the dashboard reads runtime metrics
  (vLLM metric names move between releases — "vLLM 0.8.x", not "recent vLLM").
- Whether this is cluster-wide / admin-only (controls the `-admin` suffix, see below).
- Known limitations.

Do not invent metric names or test results. If the contributor hasn't deployed and checked the
dashboard yet, say so plainly rather than filling the README with assumptions.

## 3. Scaffold the directory

```
dashboards/<slug>/
├── README.md
├── perses/
│   └── <slug>.yaml        # if Perses
└── grafana/
    ├── <slug>.json        # if Grafana
    └── <slug>-cr.yaml
```

At least one of `perses/` or `grafana/` is required; both is fine. `<slug>` is lowercase and
hyphenated, matching the dashboard's subject, not its format.

## 4. Build the Perses manifest

Use `templates/perses-dashboard.yaml` as the starting point — it already satisfies every rule
`validation/scripts/validate_dashboards.sh` enforces:

- `apiVersion: perses.dev/v1alpha2`, dashboard definition under `spec.config`.
- `metadata.namespace: redhat-ods-monitoring` (the namespace that holds the datasource — a
  dashboard anywhere else applies cleanly and renders every panel empty with no error).
- `metadata.name` matches `dashboard-99-<slug>[-admin]`. **Use `99`, not any lower number** —
  that's what the validator regex requires and what sorts a community dashboard after the
  built-ins.
- Add `-admin` to the name only if the dashboard is genuinely cluster-wide (see
  `custom-dashboards.adoc`'s naming section) — it hides the tab from users without
  `cluster-monitoring-view`, nothing more.
- `spec.config.display.name` starts with `"[C] - "`.
- Every `datasource.name`, at any depth, is one of `data-science-prometheus-datasource` /
  `cluster-prometheus-datasource`.
- No query hardcodes `model_name=` or `model=` to a literal — use a `ListVariable` with a
  `PrometheusLabelValuesVariable` plugin instead, scoped with `matchers` to the metric the panel
  actually uses (see the template, or `deploy-perses.adoc`'s minimal example).
- Quote every `"y"` key under `layouts` — unquoted, YAML 1.1 reads it as boolean `true` and the
  panel silently loses its vertical position.
- `$ref` targets stay `#/spec/panels/<key>`, never `#/spec/config/panels/<key>`, even though the
  panels live under `spec.config.panels` — the ref resolves against the Perses spec, not the k8s
  object.

For Grafana, drop the exported dashboard JSON into `grafana/<slug>.json` plus the
`GrafanaDashboard` resource that wraps it into `grafana/<slug>-cr.yaml`. Strip any datasource UID
or cluster URL the export embedded — check the whole file, not just the queries.

Don't try to keep a Perses and a Grafana version of the same dashboard in lock-step: Perses in the
shipped Cluster Observability Operator build has no bar gauges, no independent Y axes, and no
table panels, so a faithful port often has to be redesigned rather than translated. Contributing
one format doesn't require the other.

## 5. Write the README

Use `templates/README.md` as the structure. Required sections, per `contributing.adoc`:

Purpose and audience, Maintainer, Tested versions, Required metrics, Deployment (the `oc apply`
command and namespace, plus anything beyond the Monitoring Stack), Known limitations, and an
optional screenshot — only with sanitised data; real model/project names are customer
identifiers.

## 6. Before anything is committed

- Scan manifests, screenshots, and README examples for credentials, tokens, customer/project
  identifiers, internal hostnames, and cluster URLs. Exported Grafana JSON especially — it often
  carries a datasource UID or the source cluster's URL.
- Parameterise anything environment-specific, or document in the README that it needs editing.

## 7. Validate

```bash
./validation/scripts/validate_dashboards.sh
```

Needs `yq` (mikefarah/yq v4) and `jq`. Fix every error it reports — warnings (e.g. `v1alpha1`
apiVersion) are allowed but worth a second look. This is exactly what CI runs on the pull request;
there's nothing to gain by skipping it locally.

## 8. Deploy and confirm it actually works

A dashboard that has only been linted has not been tested. Hand off to the **deploy-dashboard**
skill to apply it to a real cluster and confirm every panel has data before opening the PR.

## 9. Open the pull request

- Branch name describes the dashboard (`add-gpu-utilization-dashboard`).
- PR description states which cluster and which OpenShift AI version it was tested on.
- Mention in the description if a Perses and Grafana version of the same dashboard intentionally
  diverge — neither CI nor human review checks that for you.
