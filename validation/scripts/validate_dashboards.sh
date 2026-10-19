#!/usr/bin/env bash
# Structural validation for dashboard contributions.
#
# Enforces the contract documented at
# https://rh-aiservices-bu.github.io/rhoai-dashboards-as-code/modules/main/repository-structure.html
#
# Every rule here has exactly one right answer, so none of it needs a language
# model: a missing README or an ad-hoc datasource is a fact, not a judgement.
# The AI review layer handles what genuinely needs an opinion.
#
# Usage:   validation/scripts/validate_dashboards.sh [dashboards-dir]
# Exit:    0 no errors (warnings allowed), 1 one or more errors
#
# Requires: yq (mikefarah/yq v4), jq

set -uo pipefail

DASHBOARDS_DIR="${1:-dashboards}"

# The datasource shipped by the RHOAI Monitoring Stack. Dashboards here must use
# it; anything else is not portable to another cluster.
OOTB_DATASOURCE="data-science-prometheus-datasource"
MONITORING_NS="redhat-ods-monitoring"
CURRENT_API="perses.dev/v1alpha2"
LEGACY_API="perses.dev/v1alpha1"
DISPLAY_PREFIX='[C] - '

ERRORS=0
WARNINGS=0
MANIFESTS=0

# GitHub Actions renders ::error:: and ::warning:: as annotations. Locally they
# are just prefixes, which is still readable.
err()  { printf '::error::%s: %s\n'   "$1" "$2"; ERRORS=$((ERRORS + 1)); }
warn() { printf '::warning::%s: %s\n' "$1" "$2"; WARNINGS=$((WARNINGS + 1)); }

need() {
  command -v "$1" >/dev/null 2>&1 && return 0
  printf 'error: %s is required but not installed.\n' "$1" >&2
  case "$1" in
    yq) printf '  macOS: brew install yq\n  Linux: see https://github.com/mikefarah/yq#install\n' >&2 ;;
    jq) printf '  macOS: brew install jq\n  Linux: apt-get install jq\n' >&2 ;;
  esac
  exit 2
}

# ---------------------------------------------------------------- perses
check_perses_file() {
  local f="$1" doc_count i
  if ! yq e 'true' "$f" >/dev/null 2>&1; then
    err "$f" "invalid YAML"
    return
  fi

  doc_count=$(yq e --no-doc 'di' "$f" 2>/dev/null | tail -1)
  doc_count=$((doc_count + 1))

  for ((i = 0; i < doc_count; i++)); do
    local kind api name ns display cfg
    kind=$(yq e "select(di == $i) | .kind // \"\"" "$f")
    [ -z "$kind" ] && continue

    if [ "$kind" != "PersesDashboard" ]; then
      err "$f" "kind is '$kind', expected 'PersesDashboard'"
      continue
    fi
    MANIFESTS=$((MANIFESTS + 1))

    api=$(yq e "select(di == $i) | .apiVersion // \"\"" "$f")
    if [ "$api" = "$LEGACY_API" ]; then
      warn "$f" "uses $LEGACY_API; the operator prefers $CURRENT_API and mixing them causes conflicts"
    elif [ "$api" != "$CURRENT_API" ]; then
      err "$f" "apiVersion is '$api', expected '$CURRENT_API'"
    fi

    name=$(yq e "select(di == $i) | .metadata.name // \"\"" "$f")
    if ! printf '%s' "$name" | grep -Eq '^dashboard-9-c-[a-z0-9]+(-[a-z0-9]+)*(-admin)?$'; then
      err "$f" "metadata.name '$name' does not match dashboard-9-c-<slug>[-admin]; ordering is alphabetical so the prefix controls placement"
    fi

    ns=$(yq e "select(di == $i) | .metadata.namespace // \"\"" "$f")
    if [ "$ns" != "$MONITORING_NS" ]; then
      err "$f" "metadata.namespace is '$ns', expected '$MONITORING_NS'; PersesDatasource is project-scoped and a dashboard elsewhere renders empty with no error"
    fi

    # v1alpha2 nests the dashboard under spec.config, v1alpha1 under spec.
    if [ "$(yq e "select(di == $i) | .spec | has(\"config\")" "$f")" = "true" ]; then
      cfg=".spec.config"
    else
      cfg=".spec"
    fi

    display=$(yq e "select(di == $i) | ${cfg}.display.name // \"\"" "$f")
    case "$display" in
      "$DISPLAY_PREFIX"*) : ;;
      *) err "$f" "display.name '$display' must start with '$DISPLAY_PREFIX' to mark it as custom" ;;
    esac

    # Datasource references, at any depth.
    local ds_count bad_ds
    ds_count=$(yq e "select(di == $i) | [${cfg} | .. | select(has(\"datasource\")) | .datasource | select(has(\"name\"))] | length" "$f")
    if [ "${ds_count:-0}" -eq 0 ]; then
      warn "$f" "no datasource reference found; panels will not resolve data"
    else
      while IFS= read -r bad_ds; do
        [ -z "$bad_ds" ] && continue
        err "$f" "datasource.name is '$bad_ds'; must be '$OOTB_DATASOURCE'"
      done < <(yq e "select(di == $i) | ${cfg} | .. | select(has(\"datasource\")) | .datasource | select(has(\"name\")) | .name | select(. != \"$OOTB_DATASOURCE\")" "$f" 2>/dev/null)
    fi

    # Hardcoded model names in queries: pins the dashboard to one cluster.
    local q
    while IFS= read -r q; do
      [ -z "$q" ] && continue
      # Read via process substitution, not a pipe: a piped while loop runs in a
      # subshell and the ERRORS increment would be discarded, so the script
      # would print errors and still exit 0.
      while IFS= read -r m; do
        [ -z "$m" ] && continue
        case "$m" in
          *'$'*) : ;;                      # uses a variable, fine
          *'""'*) : ;;                     # empty matcher, not a pin
          *) err "$f" "query pins ${m}; use a ListVariable so the dashboard works on other clusters" ;;
        esac
      done < <(printf '%s' "$q" | grep -oE '\b(model_name|model)[[:space:]]*=~?[[:space:]]*"[^"]*"')
    done < <(yq e "select(di == $i) | [${cfg} | .. | select(has(\"query\")) | .query | select(. == \"*\")] | .[]" "$f" 2>/dev/null)
  done
}

# --------------------------------------------------------------- grafana
check_grafana_dir() {
  local d="$1" found=0 j
  for j in "$d"/*.json; do
    [ -e "$j" ] || continue
    found=1
    jq empty "$j" >/dev/null 2>&1 || err "$j" "invalid JSON"
  done
  [ "$found" -eq 0 ] && err "$d" "grafana/ present but contains no .json dashboard"
  return 0
}

# ------------------------------------------------------------- directory
check_dashboard_dir() {
  local d="$1" base f found
  base=$(basename "$d")

  printf '%s' "$base" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$' \
    || err "$d" "directory name must be lowercase and hyphenated"

  [ -f "$d/README.md" ] \
    || err "$d" "missing README.md; without it nobody can tell which metrics the dashboard needs"

  if [ ! -d "$d/perses" ] && [ ! -d "$d/grafana" ]; then
    err "$d" "must contain perses/ or grafana/ (or both)"
    return 0
  fi

  if [ -d "$d/perses" ]; then
    found=0
    for f in "$d"/perses/*.yaml "$d"/perses/*.yml; do
      [ -e "$f" ] || continue
      found=1
      check_perses_file "$f"
    done
    [ "$found" -eq 0 ] && err "$d/perses" "present but contains no YAML manifest"
  fi

  [ -d "$d/grafana" ] && check_grafana_dir "$d/grafana"
  return 0
}

# ------------------------------------------------------------------ main
need yq
need jq

if [ ! -d "$DASHBOARDS_DIR" ]; then
  printf 'no %s/ directory, nothing to validate\n' "$DASHBOARDS_DIR"
  exit 0
fi

DIRS=0
for d in "$DASHBOARDS_DIR"/*/; do
  [ -d "$d" ] || continue
  DIRS=$((DIRS + 1))
  check_dashboard_dir "${d%/}"
done

if [ "$DIRS" -eq 0 ]; then
  printf '%s/ holds no dashboard directories yet, nothing to validate\n' "$DASHBOARDS_DIR"
  exit 0
fi

printf 'dashboard directories: %d\n' "$DIRS"
printf 'Perses manifests checked: %d\n\n' "$MANIFESTS"

if [ "$ERRORS" -gt 0 ]; then
  printf 'FAIL  %d error(s), %d warning(s)\n' "$ERRORS" "$WARNINGS"
  exit 1
fi
printf 'PASS  0 errors, %d warning(s)\n' "$WARNINGS"
exit 0
