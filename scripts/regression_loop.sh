#!/usr/bin/env bash
# regression_loop.sh — iterative / repeated regression runner.
#
# Runs the suite N times back-to-back, each iteration isolated under
# out/iter-<n>/, then merges everything and reports *stability*: a test that
# passes on some iterations and fails on others is flaky and is called out
# separately from a hard regression (fails every time).
#
# This is the "반복적으로 회귀테스트" loop — useful for shaking out
# order-dependent / timing regressions that a single run can miss.
#
# Usage:
#   scripts/regression_loop.sh [ITERATIONS] [CHAPTER]
#     ITERATIONS  default 3
#     CHAPTER     optional; restrict to one tests/<chapter> package
#
# Env:
#   MODE         dry-run (default) | integration | canary
#   KEEP_GOING   if "1", do not stop early on the first failing iteration

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ITER="${1:-3}"
CHAPTER="${2:-}"
MODE="${MODE:-dry-run}"
KEEP_GOING="${KEEP_GOING:-0}"

PKG="./tests/..."
[ -n "$CHAPTER" ] && PKG="./tests/${CHAPTER}/..."

rm -rf out/iter-* out/loop-results.json
echo "regression_loop: ${ITER} iteration(s), MODE=${MODE}, pkg=${PKG}"

for n in $(seq 1 "$ITER"); do
  echo ""
  echo "===== iteration ${n}/${ITER} ====="
  idir="$ROOT/out/iter-${n}"
  mkdir -p "$idir"
  rc=0
  MODE="$MODE" OUTPUT_DIR="$idir" \
    go test "$PKG" -v -count=1 -timeout 60m -json > "$idir/gotest.jsonl" 2>&1 || rc=$?
  # Surface a quick per-iteration tail.
  grep -E '"Action":"(pass|fail|skip)","Package".*"Test"' "$idir/gotest.jsonl" \
    | jq -r 'select(.Test|test("^Test[^/]+$")) | "  [\(.Action)] \(.Test)"' 2>/dev/null \
    | sort -u || true
  if [ "$rc" -ne 0 ] && [ "$KEEP_GOING" != "1" ]; then
    echo "iteration ${n} had failures; stopping early (set KEEP_GOING=1 to continue)."
    break
  fi
done

echo ""
echo "===== stability across iterations ====="

# Merge every iteration's reporter output and compute per-test status spread.
mapfile -t FILES < <(find out -type f -path 'out/iter-*/results.json' | sort)
if [ "${#FILES[@]}" -eq 0 ]; then
  echo "no per-iteration results.json produced (tests may have skipped before recording)."
  exit 0
fi

jq -s '
  add
  | group_by(.test)
  | map({
      test: .[0].test,
      chapter: .[0].chapter,
      runs: length,
      pass: ([.[]|select(.status=="pass")]|length),
      fail: ([.[]|select(.status=="fail")]|length),
      skip: ([.[]|select(.status=="skip")]|length)
    })
  | map(. + {verdict:
      (if .fail==.runs then "REGRESSION"
       elif .fail>0 then "FLAKY"
       elif .pass>0 then "stable-pass"
       else "skipped" end)})
  | sort_by(.test)
' "${FILES[@]}" | tee out/loop-results.json \
  | jq -r '.[] | "  [\(.verdict)] \(.test)  (pass \(.pass) / fail \(.fail) / skip \(.skip) of \(.runs))"'

REG=$(jq '[.[]|select(.verdict=="REGRESSION")]|length' out/loop-results.json)
FLK=$(jq '[.[]|select(.verdict=="FLAKY")]|length' out/loop-results.json)
echo ""
echo "regressions: ${REG}, flaky: ${FLK}  (full: out/loop-results.json)"
[ "${REG}" -eq 0 ] && [ "${FLK}" -eq 0 ]
