#!/usr/bin/env bash
# Structural validation for dashboard contributions.
#
# Enforces the contract documented at
# https://rh-aiservices-bu.github.io/rhoai-community-dashboards/modules/main/repository-structure.html
#
# Every rule here has exactly one right answer, so none of it needs a language
# model: a missing README or an ad-hoc datasource is a fact, not a judgement.
# The AI review layer handles what genuinely needs an opinion.
#
# Also checks the two sources the dashboard index is generated from: each dashboard's
# metadata.yaml and dashboards/register.yaml. Generation runs unattended after merge, so a bad
# source has to fail here, on the pull request, rather than publish a broken index.
#
# Usage:   validation/scripts/validate_dashboards.sh [dashboards-dir]
# Exit:    0 no errors (warnings allowed), 1 one or more errors
#
# Requires: yq (mikefarah/yq v4), jq

set -uo pipefail

DASHBOARDS_DIR="${1:-dashboards}"

# The datasources shipped by the RHOAI Monitoring Stack. Dashboards here must
# use one of these; anything else is not portable to another cluster.
OOTB_DATASOURCES=("data-science-prometheus-datasource" "cluster-prometheus-datasource")
MONITORING_NS="redhat-ods-monitoring"
CURRENT_API="perses.dev/v1alpha2"
LEGACY_API="perses.dev/v1alpha1"
DISPLAY_PREFIX='[C] - '
REGISTER_FILE="$DASHBOARDS_DIR/register.yaml"
# Keeps the generated index scannable. Prose belongs in the dashboard's README, not in a cell.
MAX_SUMMARY=200

ERRORS=0
WARNINGS=0
MANIFESTS=0
REGISTER_ENTRIES=0

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
    if ! printf '%s' "$name" | grep -Eq '^dashboard-99-[a-z0-9]+(-[a-z0-9]+)*(-admin)?$'; then
      err "$f" "metadata.name '$name' does not match dashboard-99-<slug>[-admin]; ordering is alphabetical so the prefix controls placement"
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
      local allowed_list
      allowed_list=$(printf '"%s",' "${OOTB_DATASOURCES[@]}")
      allowed_list="[${allowed_list%,}]"
      while IFS= read -r bad_ds; do
        [ -z "$bad_ds" ] && continue
        err "$f" "datasource.name is '$bad_ds'; must be one of: ${OOTB_DATASOURCES[*]}"
      done < <(yq e "select(di == $i) | ${cfg} | .. | select(has(\"datasource\")) | .datasource | select(has(\"name\")) | .name | select(. != null) | select(. as \$n | ${allowed_list} | contains([\$n]) | not)" "$f" 2>/dev/null)
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
# Two shapes are valid, because both deploy with a single oc apply:
#   1. a GrafanaDashboard CR in YAML with the dashboard inline in spec.json
#   2. a raw dashboard .json, usually next to a CR that references it
# Requiring .json only would reject shape 1, which is the tidier of the two.
check_grafana_dir() {
  local d="$1" found=0 f kind embedded
  for f in "$d"/*.json; do
    [ -e "$f" ] || continue
    found=1
    jq empty "$f" >/dev/null 2>&1 || err "$f" "invalid JSON"
  done
  for f in "$d"/*.yaml "$d"/*.yml; do
    [ -e "$f" ] || continue
    found=1
    if ! yq e 'true' "$f" >/dev/null 2>&1; then
      err "$f" "invalid YAML"
      continue
    fi
    kind=$(yq e '.kind // ""' "$f")
    if [ "$kind" != "GrafanaDashboard" ]; then
      err "$f" "kind is '$kind', expected 'GrafanaDashboard'"
      continue
    fi
    # spec.json holds the dashboard itself; a malformed blob renders nothing.
    if [ "$(yq e '.spec | has("json")' "$f")" = "true" ]; then
      embedded=$(yq e '.spec.json' "$f")
      printf '%s' "$embedded" | jq empty >/dev/null 2>&1 \
        || err "$f" "spec.json does not parse as JSON"
    fi
  done
  [ "$found" -eq 0 ] \
    && err "$d" "grafana/ present but contains no dashboard (.json or a GrafanaDashboard .yaml)"
  return 0
}

# -------------------------------------------------------------- metadata
# dashboards/<slug>/metadata.yaml is what the dashboard index is generated from. It is checked
# here rather than in the generator so a contribution fails on the pull request, at the same
# gate as everything else, instead of after merge when the index is rebuilt unattended.
check_metadata() {
  local d="$1" meta="$1/metadata.yaml"
  local field value title display expected found=0 f i doc_count

  if [ ! -f "$meta" ]; then
    err "$d" "missing metadata.yaml; the dashboard index is generated from it and cannot list a dashboard without one"
    return 0
  fi
  if ! yq e 'true' "$meta" >/dev/null 2>&1; then
    err "$meta" "invalid YAML"
    return 0
  fi

  for field in title summary audience maintainer rhoai; do
    value=$(yq e ".${field} // \"\"" "$meta" | tr '\n' ' ' | sed -e 's/  */ /g' -e 's/^ *//' -e 's/ *$//')
    if [ -z "$value" ]; then
      err "$meta" "$field is missing or empty"
      continue
    fi
    # A pipe breaks both generated table formats; a tab breaks the records the generator sorts.
    case "$value" in
      *'|'*) err "$meta" "$field contains '|', which breaks the generated tables" ;;
    esac
    case "$value" in
      *"$(printf '\t')"*) err "$meta" "$field contains a tab, which breaks the generated index" ;;
    esac
    case "$field" in
      summary)
        [ "${#value}" -gt "$MAX_SUMMARY" ] && err "$meta" \
          "summary is ${#value} characters; keep it under $MAX_SUMMARY so the index stays scannable"
        ;;
      maintainer)
        printf '%s' "$value" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9-]*$' || err "$meta" \
          "maintainer '$value' must be a bare GitHub handle, with no @ and no URL; the index builds the link"
        ;;
    esac
  done

  # title is what the index shows and display.name is what the console shows: two copies of one
  # fact, so they are checked against each other rather than left to drift.
  title=$(yq e '.title // ""' "$meta")
  [ -n "$title" ] || return 0
  [ -d "$d/perses" ] || return 0

  for f in "$d"/perses/*.yaml "$d"/perses/*.yml; do
    [ -e "$f" ] || continue
    yq e 'true' "$f" >/dev/null 2>&1 || continue
    doc_count=$(yq e --no-doc 'di' "$f" 2>/dev/null | tail -1)
    doc_count=$((doc_count + 1))
    for ((i = 0; i < doc_count; i++)); do
      if [ "$(yq e "select(di == $i) | .spec | has(\"config\")" "$f")" = "true" ]; then
        display=$(yq e "select(di == $i) | .spec.config.display.name // \"\"" "$f")
      else
        display=$(yq e "select(di == $i) | .spec.display.name // \"\"" "$f")
      fi
      [ -n "$display" ] || continue
      expected=${display#"$DISPLAY_PREFIX"}
      [ "$expected" = "$title" ] && found=1
    done
  done

  [ "$found" -eq 1 ] || err "$meta" \
    "title '$title' matches no display.name under $d/perses (expected '${DISPLAY_PREFIX}${title}'); the index and the console would disagree"
  return 0
}

# -------------------------------------------------------------- register
# dashboards/register.yaml is the other source the index is generated from: one entry per
# repository that keeps its own dashboards, with the dashboards it ships nested under it.
check_register() {
  local f="$REGISTER_FILE"
  local count i j dcount repo maintainer url details field value

  if [ ! -f "$f" ]; then
    err "$f" "not found; it is a source for the generated index, so it exists even when empty"
    return 0
  fi
  if ! yq e 'true' "$f" >/dev/null 2>&1; then
    err "$f" "invalid YAML"
    return 0
  fi
  if [ "$(yq e 'type' "$f")" != "!!seq" ]; then
    err "$f" "must be a list of repositories"
    return 0
  fi

  count=$(yq e 'length' "$f")
  for ((i = 0; i < count; i++)); do
    REGISTER_ENTRIES=$((REGISTER_ENTRIES + 1))
    repo=$(yq e ".[$i].repo // \"\"" "$f")
    maintainer=$(yq e ".[$i].maintainer // \"\"" "$f")

    case "$repo" in
      https://github.com/*/*) : ;;
      "") err "$f" "entry $i has no repo" ;;
      *) err "$f" "entry $i repo '$repo' must be a https://github.com/<owner>/<name> URL; owner/name is derived from it" ;;
    esac

    printf '%s' "$maintainer" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9-]*$' || err "$f" \
      "entry $i maintainer '$maintainer' must be a bare GitHub handle, with no @ and no URL"

    dcount=$(yq e ".[$i].dashboards | length" "$f" 2>/dev/null)
    case "$dcount" in ''|null) dcount=0 ;; esac
    if [ "$dcount" -eq 0 ]; then
      err "$f" "entry $i ($repo) lists no dashboards; an entry exists to point at a dashboard"
      continue
    fi

    for ((j = 0; j < dcount; j++)); do
      for field in title format url required_data; do
        value=$(yq e ".[$i].dashboards[$j].${field} // \"\"" "$f" | tr '\n' ' ' | sed -e 's/ *$//')
        if [ -z "$value" ]; then
          err "$f" "entry $i dashboard $j: $field is missing or empty"
          continue
        fi
        case "$value" in
          *'|'*) err "$f" "entry $i dashboard $j: $field contains '|', which breaks the generated tables" ;;
        esac
      done

      url=$(yq e ".[$i].dashboards[$j].url // \"\"" "$f")
      case "$url" in
        ''|https://*) : ;;
        *) err "$f" "entry $i dashboard $j: url '$url' must start with https://" ;;
      esac

      # An entry too long for a row gets its own page in dashboards/; a dead link to one is
      # worse than no link.
      details=$(yq e ".[$i].dashboards[$j].details // \"\"" "$f")
      if [ -n "$details" ] && [ ! -f "$DASHBOARDS_DIR/$details" ]; then
        err "$f" "entry $i dashboard $j: details '$details' does not exist in $DASHBOARDS_DIR/"
      fi
    done
  done
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

  check_metadata "$d"

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

check_register

if [ "$DIRS" -eq 0 ]; then
  printf '%s/ holds no dashboard directories yet, nothing to validate\n' "$DASHBOARDS_DIR"
  exit 0
fi

printf 'dashboard directories: %d\n' "$DIRS"
printf 'Perses manifests checked: %d\n' "$MANIFESTS"
printf 'register entries checked: %d\n\n' "$REGISTER_ENTRIES"

if [ "$ERRORS" -gt 0 ]; then
  printf 'FAIL  %d error(s), %d warning(s)\n' "$ERRORS" "$WARNINGS"
  exit 1
fi
printf 'PASS  0 errors, %d warning(s)\n' "$WARNINGS"
exit 0
