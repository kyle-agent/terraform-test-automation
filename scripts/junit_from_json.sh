#!/usr/bin/env bash
# junit_from_json.sh
#
# Convert `go test -json` output into a minimal JUnit XML so GitHub Actions
# can render per-test results in the run summary without an extra tool.
#
# Usage: junit_from_json.sh out/results.json out/junit.xml

set -euo pipefail

IN=${1:-out/results.json}
OUT=${2:-out/junit.xml}

if [ ! -f "$IN" ]; then
  echo "no input file: $IN"
  exit 0
fi

# results.json from the reporter has objects like:
#   {"test":"...","status":"pass","duration_ms":1234, ...}
jq -r '
  def esc: gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;") | gsub("\""; "&quot;");
  "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
  "<testsuites>",
  "  <testsuite name=\"regression\" tests=\"" + (length|tostring) +
    "\" failures=\"" + ([.[]|select(.status=="fail")]|length|tostring) +
    "\" skipped=\"" + ([.[]|select(.status=="skip")]|length|tostring) + "\">",
  ( .[] |
    "    <testcase classname=\"" + (.chapter|esc) +
      "\" name=\"" + (.test|esc) +
      "\" time=\"" + ((.duration_ms/1000)|tostring) + "\">" +
    ( if .status == "fail" then
        "<failure message=\"" + (.summary|esc) + "\"/>"
      elif .status == "skip" then
        "<skipped/>"
      else
        ""
      end ) +
    "</testcase>"
  ),
  "  </testsuite>",
  "</testsuites>"
' "$IN" > "$OUT"
echo "wrote $OUT"
