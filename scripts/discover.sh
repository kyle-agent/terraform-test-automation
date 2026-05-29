#!/usr/bin/env bash
# discover.sh — emit a *dynamic* view of the regression suite.
#
# The CI workflow does not hard-code which chapters or scenarios exist; it asks
# this script at run time. Adding a new tests/<chapter>/ package or a new
# scenarios/<name>/ directory makes it show up in the next run automatically.
#
# Usage:
#   discover.sh chapters      # JSON matrix of test packages (default)
#   discover.sh scenarios     # JSON matrix of scenario dirs
#   discover.sh list          # human-readable summary
#
# In GitHub Actions:
#   echo "matrix=$(scripts/discover.sh chapters)" >> "$GITHUB_OUTPUT"

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# List chapter packages under tests/, excluding the shared common package and
# any package that contains no test files.
chapter_dirs() {
  for d in tests/*/; do
    name="${d#tests/}"; name="${name%/}"
    [ "$name" = "common" ] && continue
    if ls "$d"*_test.go >/dev/null 2>&1; then
      echo "$name"
    fi
  done
}

scenario_dirs() {
  for d in scenarios/*/; do
    name="${d#scenarios/}"; name="${name%/}"
    if ls "$d"*.tf >/dev/null 2>&1; then
      echo "$name"
    fi
  done
}

# Count test functions in a chapter package (best-effort; falls back to grep so
# it works even without a working Go toolchain in the runner step).
count_tests() {
  local pkg="$1"
  if command -v go >/dev/null 2>&1; then
    go test -list '.*' "./tests/${pkg}/..." 2>/dev/null \
      | grep -cE '^Test' || true
  else
    grep -rhoE '^func (Test[A-Za-z0-9_]+)' "tests/${pkg}/" 2>/dev/null | wc -l | tr -d ' '
  fi
}

emit_chapters_matrix() {
  local items=() name count
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    count="$(count_tests "$name")"
    items+=("$(jq -n --arg c "$name" --arg p "./tests/${name}/..." --argjson n "${count:-0}" \
      '{chapter:$c, package:$p, tests:$n}')")
  done < <(chapter_dirs)
  printf '%s\n' "${items[@]}" | jq -s '{include: .}' -c
}

emit_scenarios_matrix() {
  local items=() name
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    items+=("$(jq -n --arg s "$name" --arg d "scenarios/${name}" '{scenario:$s, dir:$d}')")
  done < <(scenario_dirs)
  printf '%s\n' "${items[@]}" | jq -s '{include: .}' -c
}

emit_list() {
  echo "Chapters (test packages):"
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    echo "  - ${name} ($(count_tests "$name") tests)"
  done < <(chapter_dirs)
  echo "Scenarios (.tf fixtures):"
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    echo "  - ${name}"
  done < <(scenario_dirs)
}

case "${1:-chapters}" in
  chapters)  emit_chapters_matrix ;;
  scenarios) emit_scenarios_matrix ;;
  list)      emit_list ;;
  *) echo "usage: discover.sh [chapters|scenarios|list]" >&2; exit 2 ;;
esac
