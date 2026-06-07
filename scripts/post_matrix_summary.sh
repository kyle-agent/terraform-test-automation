#!/usr/bin/env bash
# post_matrix_summary.sh — always-on observability for the capability matrix.
#
# Unlike report_failures_to_issue.sh (which is silent when there are zero
# failures), this posts the matrix outcome for EVERY run — pass, blocked, or
# fail — so an on-demand probe's result is visible from the tracking issue
# without having to read the CI artifact / step summary.
#
# Usage: post_matrix_summary.sh [path/to/capability-matrix.json]
set -euo pipefail

IN=${1:-out/capability-matrix.json}
REPO=${REPO:-${GITHUB_REPOSITORY:-}}
TOKEN=${GITHUB_TOKEN:-${GH_TOKEN:-}}
MARKER="${ISSUE_MARKER:-[capability] matrix failures}"
RUN_URL="${GITHUB_SERVER_URL:-https://github.com}/${REPO}/actions/runs/${GITHUB_RUN_ID:-}"

if [ ! -f "$IN" ]; then
  echo "no matrix file: $IN"; exit 0
fi
# A no-op run (e.g. MATRIX_SCENARIOS matched nothing) marshals an empty slice as
# `null`; jq '.[]' would then error "Cannot iterate over null". Treat null/empty/
# non-array as "nothing to summarize" and exit cleanly so the run stays green.
COUNT=$(jq 'if type=="array" then length else 0 end' "$IN" 2>/dev/null || echo 0)
if [ "${COUNT:-0}" = "0" ]; then
  echo "matrix has 0 resources; nothing to post."; exit 0
fi
if [ -z "$TOKEN" ] || [ -z "$REPO" ]; then
  echo "GITHUB_TOKEN/REPO not set; skipping matrix summary."; exit 0
fi

# Build a Markdown summary: per-stage tally + a row per scenario with its
# stage outcomes and note (the captured attrs=/replace=/firstError detail).
BODY=$(jq -r --arg run "$RUN_URL" '
  ( [ .[].stages | to_entries[] | .value ] ) as $all
  | "## Capability matrix outcome",
    "",
    "Run: \($run)",
    "",
    "Resources: \(length) · ✅ ok: \([$all[]|select(.=="ok")]|length) · ❌ fail: \([$all[]|select(.=="fail")]|length) · 🚫 unsupported: \([$all[]|select(.=="unsupported")]|length) · 🚧 blocked: \([$all[]|select(.=="blocked")]|length) · ⊘ skip: \([$all[]|select(.=="skip")]|length)",
    "",
    "| resource | validate | plan | apply | replan | update | import | destroy | note |",
    "|---|---|---|---|---|---|---|---|---|",
    ( .[]
      | "| `\(.resource // .scenario)` | \(.stages.validate // "-") | \(.stages.plan // "-") | \(.stages.apply // "-") | \(.stages.replan // "-") | \(.stages.update // "-") | \(.stages.import // "-") | \(.stages.destroy // "-") | \((.note // "")|gsub("\n";" ")|gsub("\\|";"\\\\|")) |" ),
    "",
    "_Auto-posted by scripts/post_matrix_summary.sh (every run, not only on failure)._"
' "$IN")

api() { # method path [data]
  local method=$1 path=$2 data=${3:-}
  if [ -n "$data" ]; then
    curl -sS -X "$method" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/${path}" -d "$data"
  else
    curl -sS \
      -H "Authorization: Bearer $TOKEN" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/${path}"
  fi
}

EXISTING=$(api GET "search/issues?q=$(printf '%s' "repo:${REPO} is:issue is:open in:title \"${MARKER}\"" | jq -sRr @uri)" \
  | jq -r '.items[0].number // empty')

if [ -n "$EXISTING" ]; then
  echo "Commenting matrix summary on existing issue #${EXISTING}"
  api POST "repos/${REPO}/issues/${EXISTING}/comments" \
    "$(jq -n --arg b "$BODY" '{body:$b}')" >/dev/null
  echo "updated issue #${EXISTING}"
else
  TITLE="${MARKER} ($(date -u +%Y-%m-%d))"
  echo "Creating tracking issue: ${TITLE}"
  api POST "repos/${REPO}/issues" \
    "$(jq -n --arg t "$TITLE" --arg b "$BODY" '{title:$t,body:$b,labels:["automated"]}')" >/dev/null
  echo "created tracking issue"
fi
