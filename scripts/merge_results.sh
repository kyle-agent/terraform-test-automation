#!/usr/bin/env bash
# merge_results.sh — fan-in step of the dynamic workflow.
#
# Each chapter shard runs in its own job and writes out/<chapter>/results.json
# (the reporter's per-process output, isolated so parallel shards never clobber
# each other). This script merges every shard into a single out/results.json,
# regenerates JUnit, and prints a Markdown summary (to $GITHUB_STEP_SUMMARY when
# running in Actions, otherwise stdout).
#
# Usage:
#   merge_results.sh [SEARCH_DIR]        # default: out
#   merge_results.sh out file1.json ...  # explicit files also accepted

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${OUTPUT_DIR:-out}"
mkdir -p "$OUT"

# Collect candidate result files: any results.json under the search root(s),
# excluding the merged target itself.
SEARCH="${1:-$OUT}"
mapfile -t FILES < <(find "$SEARCH" -type f -name 'results.json' ! -path "$OUT/results.json" 2>/dev/null | sort)

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "merge_results: no per-shard results.json found under $SEARCH" >&2
  echo '[]' > "$OUT/results.json"
else
  # Concatenate the per-shard arrays; keep the last entry per test name so a
  # re-run within a shard supersedes an earlier attempt.
  jq -s 'add
    | group_by(.test)
    | map(max_by(.started_at // ""))
    | sort_by(.chapter, .test)' "${FILES[@]}" > "$OUT/results.json"
fi

# Regenerate JUnit from the merged file (best-effort).
"$ROOT/scripts/junit_from_json.sh" "$OUT/results.json" "$OUT/junit.xml" >/dev/null 2>&1 || true

# Build the Markdown summary.
summary() {
  local total pass fail skip
  total=$(jq 'length' "$OUT/results.json")
  pass=$(jq '[.[]|select(.status=="pass")]|length' "$OUT/results.json")
  fail=$(jq '[.[]|select(.status=="fail")]|length' "$OUT/results.json")
  skip=$(jq '[.[]|select(.status=="skip")]|length' "$OUT/results.json")

  echo "## Dynamic Regression Summary"
  echo ""
  echo "| total | ✅ pass | ❌ fail | ⏭️ skip |"
  echo "|---|---|---|---|"
  echo "| ${total} | ${pass} | ${fail} | ${skip} |"
  echo ""
  if [ "${fail}" -gt 0 ]; then
    echo "### ❌ Failures (regressions)"
    echo ""
    echo "| test | chapter | severity | issue | summary |"
    echo "|---|---|---|---|---|"
    jq -r '.[]|select(.status=="fail")
      | "| `\(.test)` | \(.chapter) | \(.severity) | \(.issue_ref) | \(.summary) |"' \
      "$OUT/results.json"
    echo ""
  fi
  # Surface coverage if any shard produced a coverage.json (the coverage shard
  # may be nested under out/<chapter>/ locally or out/results-coverage/ in CI).
  local covfile
  covfile=$(find "$SEARCH" "$OUT" -type f -name 'coverage.json' 2>/dev/null | head -1)
  if [ -n "$covfile" ]; then
    local pct cov tot
    pct=$(jq -r '.percent | (.*10|round)/10' "$covfile")
    cov=$(jq -r '.covered|length' "$covfile")
    tot=$(jq -r '.total_resources' "$covfile")
    echo "### Resource coverage: ${cov}/${tot} (${pct}%)"
    echo ""
  fi
}

OUTPUT_MD="$(summary)"
echo "$OUTPUT_MD"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo "$OUTPUT_MD" >> "$GITHUB_STEP_SUMMARY"
fi

# Exit non-zero if any failures, so the aggregate job reflects regression state.
FAILS=$(jq '[.[]|select(.status=="fail")]|length' "$OUT/results.json")
[ "${FAILS}" -eq 0 ]
