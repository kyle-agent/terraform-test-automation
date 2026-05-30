#!/usr/bin/env bash
# matrix_to_results.sh
#
# Convert out/capability-matrix.json into the reporter's results.json shape so
# the existing scripts/report_failures_to_issue.sh can auto-file matrix
# failures as a tracking issue. Each resource that has a "fail" stage becomes
# one failing result, with the failing stage + note carried in `details`.
#
# Usage: matrix_to_results.sh [in=out/capability-matrix.json] [out=out/results.json]

set -euo pipefail

IN=${1:-out/capability-matrix.json}
OUT=${2:-out/results.json}

if [ ! -f "$IN" ]; then
  echo "no capability matrix: $IN"; exit 0
fi

jq '
  [ .[]
    | . as $r
    | ( ["validate","plan","apply","replan","destroy"]
        | map(select($r.stages[.] == "fail")) | .[0] ) as $stage
    | select($stage != null)
    | {
        test: ($r.resource // $r.scenario),
        chapter: "capability-matrix",
        issue_ref: "kyle-agent/terraform-test-automation (capability matrix)",
        severity: (if $stage=="apply" or $stage=="validate" then "high" else "medium" end),
        status: "fail",
        mode: "integration",
        summary: ("fails at stage: " + $stage),
        details: (($r.note // "") | if . == "" then ("stage " + $stage + " failed") else . end)
      }
  ]
' "$IN" > "$OUT"

echo "wrote $OUT ($(jq 'length' "$OUT") failing resource(s) from matrix)"
