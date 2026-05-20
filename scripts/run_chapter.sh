#!/usr/bin/env bash
# Local convenience wrapper.
set -euo pipefail
CH=${1:-chapter1_core}
shift || true
MODE=${MODE:-dry-run} go test "./tests/${CH}/..." -v -timeout 60m "$@"
