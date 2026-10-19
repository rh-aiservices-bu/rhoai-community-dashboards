#!/usr/bin/env bash
# Advisory AI review of a pull request diff, via an OpenAI-compatible endpoint.
#
# Points at RHOAI Models-as-a-Service on the TMM cluster. This is NOT
# CodeRabbit: CodeRabbit's hosted app runs its own models and exposes no
# setting for a custom base URL, so a self-managed endpoint cannot be plugged
# into it. This job is the part that can use our own endpoint, and complements
# rather than replaces .coderabbit.yaml.
#
# Deterministic rules live in validate_dashboards.sh. This asks only for
# judgement a script cannot give, and never fails the build.
#
# Usage:   validation/scripts/ai_review.sh <diff-file>
# Writes the review to stdout as Markdown.
#
# Environment:
#   MAAS_BASE_URL   e.g. https://maas.apps.ocp.cloud.rhai-tmm.dev/v1
#   MAAS_API_KEY    bearer token
#   MAAS_MODEL      model id
#
# Requires: curl, jq

set -uo pipefail

DIFF_FILE="${1:-pr.diff}"
MAX_DIFF_CHARS=60000
TIMEOUT=300

# Advisory job: every failure path prints a note and exits 0 so a flaky
# endpoint never blocks a contributor's pull request.
skip() { printf '_AI review skipped: %s_\n' "$1"; exit 0; }

command -v jq   >/dev/null 2>&1 || skip "jq is not installed"
command -v curl >/dev/null 2>&1 || skip "curl is not installed"

: "${MAAS_BASE_URL:=}"
: "${MAAS_API_KEY:=}"
: "${MAAS_MODEL:=}"

[ -n "$MAAS_BASE_URL" ] || skip "endpoint not configured"
[ -n "$MAAS_API_KEY" ]  || skip "API key not configured"
[ -n "$MAAS_MODEL" ]    || skip "model not configured"
[ -f "$DIFF_FILE" ]     || skip "no diff file at $DIFF_FILE"

BASE_URL="${MAAS_BASE_URL%/}"

DIFF=$(cat "$DIFF_FILE")
[ -n "${DIFF//[[:space:]]/}" ] || skip "no reviewable changes in this pull request"

TRUNCATED=0
if [ "${#DIFF}" -gt "$MAX_DIFF_CHARS" ]; then
  DIFF="${DIFF:0:$MAX_DIFF_CHARS}"
  TRUNCATED=1
fi

read -r -d '' SYSTEM <<'PROMPT'
You are reviewing a pull request to a repository of Perses and Grafana
dashboards for Red Hat OpenShift AI.

Deterministic checks already run in CI and you must NOT repeat them: directory
layout, README presence, the [C] - display prefix, dashboard-9-c-<slug>
resource naming, the redhat-ods-monitoring namespace, use of the
data-science-prometheus-datasource, and hardcoded model names. Assume all of
that is handled.

Review only what needs judgement:
- Is the PromQL correct, and does it answer what the panel title and README claim?
- Counter vs gauge errors: a counter plotted without rate() or increase(), or
  rate() applied to a gauge.
- Aggregations dropping a label they need, or keeping one that makes the series
  meaningless.
- Variables declared but unused, or used but undeclared.
- Panel $ref targets that do not exist. On perses.dev/v1alpha2 refs stay
  "#/spec/panels/<key>" even though panels sit under spec.config.panels.
- Unquoted "y" keys in layouts: YAML 1.1 reads y as boolean true and the
  vertical position is silently lost.
- Documentation claims that overstate what exists in the repository.
- Em dashes in prose, which this project does not use.

Rules for your output:
- Be specific. Quote the exact line or key you mean.
- If you are unsure whether something is wrong, say so rather than asserting.
- Do not invent metric names, files or conventions.
- If you find nothing worth raising, say exactly that. Do not pad.
- Maximum 10 points, ordered most to least important. Markdown, no preamble.
PROMPT

# Build the request with jq so the diff is escaped correctly rather than by
# hand.
#
# No max_tokens is set on purpose. glm-53-flash is a reasoning model: it spends
# tokens on an internal trace before emitting any content, so a cap that is too
# low returns finish_reason "length" with content still null and the review is
# silently lost. Measured on a real dashboard diff: ~900-1800 reasoning tokens
# before ~250-300 of actual content. The endpoint allows 3,000,000 tokens per
# minute, so there is nothing to save by capping, and omitting it lets the
# server allow the remaining context. If a server default ever does truncate,
# the finish_reason check below reports it rather than failing silently.
PAYLOAD=$(jq -n \
  --arg model "$MAAS_MODEL" \
  --arg system "$SYSTEM" \
  --arg diff "$DIFF" \
  '{
     model: $model,
     temperature: 0.2,
     messages: [
       {role: "system", content: $system},
       {role: "user",   content: ("Review this diff.\n\n```diff\n" + $diff + "\n```")}
     ]
   }')

HTTP_BODY=$(mktemp)
trap 'rm -f "$HTTP_BODY"' EXIT

HTTP_CODE=$(curl -sS --max-time "$TIMEOUT" -o "$HTTP_BODY" -w '%{http_code}' \
  -X POST "${BASE_URL}/chat/completions" \
  -H "Authorization: Bearer ${MAAS_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" 2>/dev/null) || skip "could not reach the endpoint"

if [ "$HTTP_CODE" != "200" ]; then
  skip "endpoint returned HTTP ${HTTP_CODE}"
fi

jq -e '.choices[0]' "$HTTP_BODY" >/dev/null 2>&1 \
  || skip "unexpected response shape"

# Reasoning models leave content null when the budget is spent mid-trace.
CONTENT=$(jq -r '.choices[0].message.content // ""' "$HTTP_BODY")
FINISH=$(jq -r '.choices[0].finish_reason // "unknown"' "$HTTP_BODY")

if [ -z "${CONTENT//[[:space:]]/}" ]; then
  printf '_AI review produced no content (finish_reason: %s). ' "$FINISH"
  printf 'The model likely spent its whole token budget reasoning._\n'
  exit 0
fi

printf '%s\n' "$CONTENT"

if [ "$TRUNCATED" -eq 1 ]; then
  printf '\n---\n_Diff truncated to %s characters; later files were not reviewed._\n' \
    "$MAX_DIFF_CHARS"
fi

printf '\n<sub>Advisory review by <code>%s</code> via RHOAI Models-as-a-Service. ' "$MAAS_MODEL"
printf 'Not a merge gate. Deterministic checks run in <b>validate dashboards</b>.</sub>\n'
