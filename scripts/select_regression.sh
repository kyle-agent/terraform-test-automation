#!/usr/bin/env bash
# select_regression.sh — emit the cost-tiered regression set.
#
# Prints, comma-separated on one line, every scenario in coverage/cost_tiers.yaml
# whose status == green AND cost in {free, cheap}. This is the known-green,
# low-cost lane that the nightly regression workflow re-runs to catch
# regressions without incurring heavy (managed-DB / SKE / baremetal) spend.
#
# Usage: scripts/select_regression.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIERS="${COST_TIERS_FILE:-$HERE/../coverage/cost_tiers.yaml}"

python3 - "$TIERS" <<'PY'
import sys, re

path = sys.argv[1]
selected = []
name = cost = status = None

def flush():
    if name and status == "excluded":
        pass  # never run excluded (e.g. cloudmonitoring, deprecating)
    elif name and status == "green" and cost in ("free", "cheap"):
        selected.append(name)

with open(path) as f:
    for raw in f:
        line = raw.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        # top-level key (scenario name): no leading whitespace, ends with ':'
        m = re.match(r'^([A-Za-z0-9_]+):\s*$', line)
        if m:
            flush()
            name, cost, status = m.group(1), None, None
            continue
        m = re.match(r'^\s+cost:\s*(\S+)', line)
        if m:
            cost = m.group(1).strip().strip('"\'')
            continue
        m = re.match(r'^\s+status:\s*(\S+)', line)
        if m:
            status = m.group(1).strip().strip('"\'')
            continue
flush()

print(",".join(selected))
PY
