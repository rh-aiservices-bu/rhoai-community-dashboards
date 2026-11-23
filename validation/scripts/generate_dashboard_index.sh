#!/usr/bin/env bash
# Generates the dashboard indexes from the repository itself.
#
# Sources:
#   dashboards/<slug>/metadata.yaml    one per in-repo dashboard, required
#   dashboards/<slug>/perses/*.yaml    read only for the -admin suffix, which sets visibility
#   dashboards/register.yaml           dashboards kept in their own repositories
#
# Outputs, all generated - never edit them by hand:
#   content/modules/ROOT/partials/dashboard-index.adoc
#   content/modules/ROOT/partials/indexed-repositories.adoc
#   dashboards/README.md, between its BEGIN/END GENERATED markers
#
# Order is deterministic (dashboards by title, repositories by owner/name), so a diff only ever
# shows a real change and CI can treat drift as an error.
#
# Usage:   validation/scripts/generate_dashboard_index.sh [--check]
#            --check  write nothing; exit 1 if the committed output is stale
# Exit:    0 written or already up to date, 1 stale output or a bad source, 2 missing tool
#
# Requires: yq (mikefarah/yq v4)

set -uo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd) || exit 2
cd "$REPO_ROOT" || exit 2

DASHBOARDS_DIR="dashboards"
REGISTER="dashboards/register.yaml"
PARTIALS="content/modules/ROOT/partials"
INDEX_PARTIAL="$PARTIALS/dashboard-index.adoc"
REPOS_PARTIAL="$PARTIALS/indexed-repositories.adoc"
README="$DASHBOARDS_DIR/README.md"
SCRIPT_REL="validation/scripts/generate_dashboard_index.sh"
GH="https://github.com"

BEGIN_MARKER="<!-- BEGIN GENERATED -->"
END_MARKER="<!-- END GENERATED -->"
TAB=$(printf '\t')

CHECK=0
ERRORS=0

# Collection writes to files rather than piping into sort: the left side of a pipe runs in a
# subshell, and every ERRORS increment made there would be silently discarded - which would
# publish an index quietly missing a dashboard.
err() { printf '::error::%s: %s\n' "$1" "$2" >&2; ERRORS=$((ERRORS + 1)); }

need() {
  command -v "$1" >/dev/null 2>&1 && return 0
  printf 'error: %s is required but not installed.\n' "$1" >&2
  printf '  macOS: brew install %s\n  Linux: see https://github.com/mikefarah/yq#install\n' "$1" >&2
  exit 2
}

case "${1:-}" in
  --check) CHECK=1 ;;
  "") : ;;
  *) printf 'usage: %s [--check]\n' "$SCRIPT_REL" >&2; exit 2 ;;
esac

need yq

# Folded YAML scalars keep their line breaks; a table cell needs one line.
oneline() { printf '%s' "$1" | tr '\n' ' ' | sed -e 's/  */ /g' -e 's/^ *//' -e 's/ *$//'; }

ryq() { oneline "$(yq e "$1 // \"\"" "$REGISTER")"; }

# ----------------------------------------------------------------- collect
# One tab-separated record per dashboard, sorted by title:
#   title, slug, summary, audience, admin, formats, rhoai, maintainer
collect_dashboards() {
  local out="$1" raw="$1.raw"
  local d slug meta title summary audience maintainer rhoai formats admin f name field
  : > "$raw"

  for d in "$DASHBOARDS_DIR"/*/; do
    [ -d "$d" ] || continue
    slug=$(basename "${d%/}")
    meta="${d}metadata.yaml"

    if [ ! -f "$meta" ]; then
      err "$d" "no metadata.yaml, so the dashboard cannot be indexed; see repository-structure.adoc"
      continue
    fi
    if ! yq e 'true' "$meta" >/dev/null 2>&1; then
      err "$meta" "invalid YAML"
      continue
    fi

    title=$(oneline "$(yq e '.title // ""' "$meta")")
    summary=$(oneline "$(yq e '.summary // ""' "$meta")")
    audience=$(oneline "$(yq e '.audience // ""' "$meta")")
    maintainer=$(oneline "$(yq e '.maintainer // ""' "$meta")")
    rhoai=$(oneline "$(yq e '.rhoai // ""' "$meta")")

    for field in title summary audience maintainer rhoai; do
      [ -n "${!field}" ] || err "$meta" "$field is missing or empty"
    done

    # Formats come from the directory, never restated in metadata.yaml.
    formats=""
    [ -d "${d}perses" ] && formats="Perses"
    if [ -d "${d}grafana" ]; then
      if [ -n "$formats" ]; then formats="$formats, Grafana"; else formats="Grafana"; fi
    fi
    [ -n "$formats" ] || err "$d" "neither perses/ nor grafana/, so there is no format to list"

    # The -admin suffix hides a dashboard from users without cluster-monitoring-view, which is
    # the first thing someone reading the index needs to know about it.
    admin="no"
    for f in "${d}perses"/*.yaml "${d}perses"/*.yml; do
      [ -e "$f" ] || continue
      while IFS= read -r name; do
        case "$name" in *-admin) admin="yes" ;; esac
      done < <(yq e '.metadata.name // ""' "$f" 2>/dev/null)
    done

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$title" "$slug" "$summary" "$audience" "$admin" "$formats" "$rhoai" "$maintainer" >> "$raw"
  done

  LC_ALL=C sort -t"$TAB" -k1,1 "$raw" > "$out"
  rm -f "$raw"
}

# Repositories, sorted by owner/name: "owner/name<TAB>index-in-register".
collect_repos() {
  local out="$1" raw="$1.raw"
  local count i repo owner_name
  : > "$raw"

  count=$(yq e 'length' "$REGISTER" 2>/dev/null)
  case "$count" in ''|null|0) count=0 ;; esac

  for ((i = 0; i < count; i++)); do
    repo=$(ryq ".[$i].repo")
    if [ -z "$repo" ]; then
      err "$REGISTER" "entry $i has no repo"
      continue
    fi
    owner_name=${repo#https://github.com/}
    owner_name=${owner_name%/}
    printf '%s\t%s\n' "$owner_name" "$i" >> "$raw"
  done

  LC_ALL=C sort -t"$TAB" -k1,1 "$raw" > "$out"
  rm -f "$raw"
}

# Dashboards inside one register entry, sorted by title: "title<TAB>index".
collect_repo_dashboards() {
  local i="$1" out="$2" raw="$2.raw"
  local count j title
  : > "$raw"

  count=$(yq e ".[$i].dashboards | length" "$REGISTER" 2>/dev/null)
  case "$count" in ''|null|0) count=0 ;; esac
  [ "$count" -eq 0 ] && err "$REGISTER" "entry $i lists no dashboards"

  for ((j = 0; j < count; j++)); do
    title=$(ryq ".[$i].dashboards[$j].title")
    if [ -z "$title" ]; then
      err "$REGISTER" "entry $i dashboard $j has no title"
      continue
    fi
    printf '%s\t%s\n' "$title" "$j" >> "$raw"
  done

  LC_ALL=C sort -t"$TAB" -k1,1 "$raw" > "$out"
  rm -f "$raw"
}

# ------------------------------------------------------------------ render
adoc_header() {
  printf '// Generated by %s - do not edit.\n' "$SCRIPT_REL"
  printf '// %s\n\n' "$1"
}

# "Who it is for", with the console-level visibility filter spelled out.
who_for() { if [ "$2" = "yes" ]; then printf '%s. Admin only' "$1"; else printf '%s' "$1"; fi; }

render_index_adoc() {
  local title slug summary audience admin formats rhoai maintainer
  adoc_header "Facts come from dashboards/<slug>/metadata.yaml; re-run the script after editing one."
  printf '[cols="2,3,2,1,1,1", options="header"]\n|===\n'
  printf '| Dashboard | What it shows | Who it is for | Formats | Tested on | Maintainer\n\n'
  while IFS="$TAB" read -r title slug summary audience admin formats rhoai maintainer; do
    [ -n "$title" ] || continue
    printf '| link:{repo-url}/tree/main/dashboards/%s[%s]\n| %s\n| %s\n| %s\n| %s\n| link:%s/%s[@%s]\n\n' \
      "$slug" "$title" "$summary" "$(who_for "$audience" "$admin")" \
      "$formats" "$rhoai" "$GH" "$maintainer" "$maintainer"
  done < "$DASHBOARD_TSV"
  printf '|===\n'
}

render_repos_adoc() {
  local owner_name i title j repo maintainer format url required details
  adoc_header "Entries come from dashboards/register.yaml; re-run the script after editing it."
  while IFS="$TAB" read -r owner_name i; do
    [ -n "$owner_name" ] || continue
    repo=$(ryq ".[$i].repo")
    maintainer=$(ryq ".[$i].maintainer")
    printf '=== link:%s[%s]\n\n' "$repo" "$owner_name"
    printf 'Maintained by link:%s/%s[@%s].\n\n' "$GH" "$maintainer" "$maintainer"
    while IFS="$TAB" read -r title j; do
      [ -n "$title" ] || continue
      format=$(ryq ".[$i].dashboards[$j].format")
      url=$(ryq ".[$i].dashboards[$j].url")
      required=$(ryq ".[$i].dashboards[$j].required_data")
      details=$(ryq ".[$i].dashboards[$j].details")
      printf 'link:%s[%s]::\n%s. Needs %s\n' "$url" "$title" "$format" "$required"
      [ -n "$details" ] && printf '+\nlink:{repo-url}/blob/main/dashboards/%s[More detail]\n' "$details"
      printf '\n'
    done < "$TMP/repo-$i.tsv"
  done < "$REPO_TSV"
}

render_readme_block() {
  local title slug summary audience admin formats rhoai maintainer
  local owner_name i j repo format url required details

  printf '%s\n' "$BEGIN_MARKER"
  printf '<!-- Generated by %s - do not edit this region by hand. -->\n\n' "$SCRIPT_REL"

  printf '## In this repository\n\n'
  printf '| Dashboard | What it shows | Who it is for | Formats | Tested on | Maintainer |\n'
  printf '| --- | --- | --- | --- | --- | --- |\n'
  while IFS="$TAB" read -r title slug summary audience admin formats rhoai maintainer; do
    [ -n "$title" ] || continue
    printf '| [%s](./%s/) | %s | %s | %s | %s | [@%s](%s/%s) |\n' \
      "$title" "$slug" "$summary" "$(who_for "$audience" "$admin")" \
      "$formats" "$rhoai" "$maintainer" "$GH" "$maintainer"
  done < "$DASHBOARD_TSV"

  printf '\n## Indexed repositories\n\n'
  while IFS="$TAB" read -r owner_name i; do
    [ -n "$owner_name" ] || continue
    repo=$(ryq ".[$i].repo")
    maintainer=$(ryq ".[$i].maintainer")
    printf '### [%s](%s)\n\n' "$owner_name" "$repo"
    printf 'Maintained by [@%s](%s/%s).\n\n' "$maintainer" "$GH" "$maintainer"
    while IFS="$TAB" read -r title j; do
      [ -n "$title" ] || continue
      format=$(ryq ".[$i].dashboards[$j].format")
      url=$(ryq ".[$i].dashboards[$j].url")
      required=$(ryq ".[$i].dashboards[$j].required_data")
      details=$(ryq ".[$i].dashboards[$j].details")
      printf -- '- **[%s](%s)** - %s. Needs %s' "$title" "$url" "$format" "$required"
      [ -n "$details" ] && printf ' [More detail](./%s)' "$details"
      printf '\n'
    done < "$TMP/repo-$i.tsv"
    printf '\n'
  done < "$REPO_TSV"

  printf '%s\n' "$END_MARKER"
}

# Replaces the marked region of dashboards/README.md and leaves the rest alone. The block comes
# in as a file because awk -v cannot portably carry a value containing newlines.
render_readme() {
  local blockfile="$1"
  if ! grep -qF "$BEGIN_MARKER" "$README" || ! grep -qF "$END_MARKER" "$README"; then
    err "$README" "missing the $BEGIN_MARKER / $END_MARKER markers that the generated tables go between"
    cat "$README"
    return 0
  fi
  awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" -v blockfile="$blockfile" '
    index($0, begin) == 1 {
      while ((getline line < blockfile) > 0) print line
      close(blockfile)
      skipping = 1
      next
    }
    index($0, end) == 1 { skipping = 0; next }
    !skipping           { print }
  ' "$README"
}

# -------------------------------------------------------------------- main
[ -d "$DASHBOARDS_DIR" ] || { printf 'no %s/ directory, nothing to generate\n' "$DASHBOARDS_DIR"; exit 0; }
[ -f "$README" ] || { printf 'error: %s not found\n' "$README" >&2; exit 2; }
[ -f "$REGISTER" ] || err "$REGISTER" "not found; the register is a source, so create it even if it is empty"
[ -d "$PARTIALS" ] || mkdir -p "$PARTIALS"

TMP=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP"' EXIT

DASHBOARD_TSV="$TMP/dashboards.tsv"
REPO_TSV="$TMP/repos.tsv"

collect_dashboards "$DASHBOARD_TSV"
: > "$REPO_TSV"
if [ -f "$REGISTER" ]; then
  collect_repos "$REPO_TSV"
  while IFS="$TAB" read -r _ idx; do
    [ -n "$idx" ] || continue
    collect_repo_dashboards "$idx" "$TMP/repo-$idx.tsv"
  done < "$REPO_TSV"
fi

if [ "$ERRORS" -gt 0 ]; then
  printf 'FAIL  %d problem(s) in the sources; nothing written\n' "$ERRORS" >&2
  exit 1
fi

render_index_adoc > "$TMP/dashboard-index.adoc"
render_repos_adoc > "$TMP/indexed-repositories.adoc"
render_readme_block > "$TMP/block.md"
render_readme "$TMP/block.md" > "$TMP/README.md"

if [ "$ERRORS" -gt 0 ]; then
  printf 'FAIL  %d problem(s) while rendering; nothing written\n' "$ERRORS" >&2
  exit 1
fi

STALE=0
sync_file() {
  if [ ! -f "$2" ] || ! diff -q "$1" "$2" >/dev/null 2>&1; then
    STALE=$((STALE + 1))
    if [ "$CHECK" -eq 1 ]; then
      printf '\n--- %s\n' "$2"
      diff -u "$2" "$1" 2>/dev/null | tail -n +3
    else
      cp "$1" "$2" && printf 'updated  %s\n' "$2"
    fi
  fi
}

sync_file "$TMP/dashboard-index.adoc" "$INDEX_PARTIAL"
sync_file "$TMP/indexed-repositories.adoc" "$REPOS_PARTIAL"
sync_file "$TMP/README.md" "$README"

if [ "$CHECK" -eq 1 ]; then
  if [ "$STALE" -gt 0 ]; then
    printf '\n::error::%d generated file(s) out of date. Run %s and commit the result.\n' \
      "$STALE" "$SCRIPT_REL" >&2
    exit 1
  fi
  printf 'PASS  generated files are up to date\n'
  exit 0
fi

[ "$STALE" -eq 0 ] && printf 'already up to date\n'
exit 0
