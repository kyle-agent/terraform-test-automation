#!/usr/bin/env bash
# publish_report.sh
#
# Reads out/results.json and, for every failing test, posts a comment to the
# corresponding sub-issue in the provider repo and re-opens it if closed.
# Designed to run from CI; needs a fine-grained GH_TOKEN with issues:write on
# kyle-agent/terraform-provider-samsungcloudplatformv2.
#
# Usage: publish_report.sh path/to/results.json

set -euo pipefail

RESULTS=${1:-out/results.json}
PROVIDER_REPO=${PROVIDER_REPO:-kyle-agent/terraform-provider-samsungcloudplatformv2}

if [ ! -f "$RESULTS" ]; then
  echo "no results file: $RESULTS"
  exit 0
fi
if [ -z "${GH_TOKEN:-}" ]; then
  echo "GH_TOKEN not set; skipping issue updates."
  exit 0
fi

# Pull failing tests + their issue ref (e.g. "owner/repo#11 (2-A)") from the
# json reporter output and group them by issue number.
mapfile -t FAILS < <(jq -r '
  .[]
  | select(.status == "fail")
  | "\(.issue_ref)\t\(.test)\t\(.summary)"
' "$RESULTS")

if [ "${#FAILS[@]}" -eq 0 ]; then
  echo "no failures"
  exit 0
fi

declare -A SEEN
for line in "${FAILS[@]}"; do
  ref=$(awk -F'\t' '{print $1}' <<<"$line")
  test=$(awk -F'\t' '{print $2}' <<<"$line")
  summary=$(awk -F'\t' '{print $3}' <<<"$line")
  # ref looks like "kyle-agent/terraform-provider-samsungcloudplatformv2#11 (2-A)"
  issue=$(grep -oE '#[0-9]+' <<<"$ref" | tr -d '#')
  subtag=$(grep -oE '\([^)]+\)' <<<"$ref" | tr -d '()' || true)
  if [ -z "$issue" ]; then
    echo "WARN: cannot parse issue from ref: $ref" >&2
    continue
  fi
  body=$(printf '## Regression detected\n\n- Test: `%s`\n- Sub-item: %s\n- Summary: %s\n\nFull JUnit / log: see CI artifact.\n' \
    "$test" "${subtag:-N/A}" "$summary")
  echo "Updating ${PROVIDER_REPO}#${issue} — ${test}"
  # Re-open if closed, then comment.
  curl -sSf -X PATCH \
    -H "Authorization: Bearer $GH_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${PROVIDER_REPO}/issues/${issue}" \
    -d '{"state":"open"}' >/dev/null
  curl -sSf -X POST \
    -H "Authorization: Bearer $GH_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${PROVIDER_REPO}/issues/${issue}/comments" \
    -d "$(jq -n --arg b "$body" '{body:$b}')" >/dev/null
  SEEN[$issue]=1
done

echo "updated ${#SEEN[@]} issue(s)"
