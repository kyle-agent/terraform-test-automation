#!/usr/bin/env bash
# report_failures_to_issue.sh
#
# Hands-off failure reporting: on any failing test in out/results.json, open (or
# update) a SINGLE tracking issue IN THIS REPO with the structured failure
# details — test name, chapter, severity, the concrete plan diff captured in
# `details`, and a link to the CI run. No need to scrape Actions logs by hand.
#
# Idempotent per run: it searches for an existing open issue with the marker
# title and, if found, adds a comment; otherwise it creates one. The body/
# comment is built entirely from results.json so it is self-contained.
#
# Auth: GITHUB_TOKEN (the default Actions token works — it has issues:write on
# the current repo). Repo is taken from GITHUB_REPOSITORY in Actions, or pass
# REPO=owner/name.
#
# Usage: report_failures_to_issue.sh [path/to/results.json]

set -euo pipefail

RESULTS=${1:-out/results.json}
REPO=${REPO:-${GITHUB_REPOSITORY:-}}
TOKEN=${GITHUB_TOKEN:-${GH_TOKEN:-}}
MARKER="[regression] integration failures"   # stable title prefix for dedup
RUN_URL="${GITHUB_SERVER_URL:-https://github.com}/${REPO}/actions/runs/${GITHUB_RUN_ID:-}"

if [ ! -f "$RESULTS" ]; then
  echo "no results file: $RESULTS"; exit 0
fi
if [ -z "$TOKEN" ] || [ -z "$REPO" ]; then
  echo "GITHUB_TOKEN/REPO not set; skipping issue reporting."; exit 0
fi

FAIL_COUNT=$(jq '[.[]|select(.status=="fail")]|length' "$RESULTS")
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "no failures; nothing to report."; exit 0
fi

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

# Build a Markdown table of failures with their captured diff details.
BODY=$(jq -r --arg run "$RUN_URL" '
  "## Integration regression — \([.[]|select(.status=="fail")]|length) failing test(s)",
  "",
  "Run: \($run)",
  "",
  "| test | chapter | severity | mode | details |",
  "|---|---|---|---|---|",
  ( .[] | select(.status=="fail")
    | "| `\(.test)` | \(.chapter) | \(.severity) | \(.mode) | \((.details // "—")|gsub("\n";" ")|gsub("\\|";"\\\\|")) |" ),
  "",
  "_Auto-filed by scripts/report_failures_to_issue.sh from out/results.json._"
' "$RESULTS")

# Find an existing OPEN tracking issue (title starts with MARKER).
EXISTING=$(api GET "search/issues?q=$(printf '%s' "repo:${REPO} is:issue is:open in:title \"${MARKER}\"" | jq -sRr @uri)" \
  | jq -r '.items[0].number // empty')

if [ -n "$EXISTING" ]; then
  echo "Commenting on existing tracking issue #${EXISTING}"
  api POST "repos/${REPO}/issues/${EXISTING}/comments" \
    "$(jq -n --arg b "$BODY" '{body:$b}')" >/dev/null
  echo "updated issue #${EXISTING}"
else
  TITLE="${MARKER} ($(date -u +%Y-%m-%d))"
  echo "Creating new tracking issue: ${TITLE}"
  NUM=$(api POST "repos/${REPO}/issues" \
    "$(jq -n --arg t "$TITLE" --arg b "$BODY" '{title:$t, body:$b, labels:["regression","automated"]}')" \
    | jq -r '.number')
  echo "created issue #${NUM}"
fi
