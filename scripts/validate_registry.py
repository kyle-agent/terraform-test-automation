#!/usr/bin/env python3
"""CI gate: coverage/registry.yaml must stay consistent with the repo.

Checks:
  * every scenarios/<dir> has a registry entry and vice versa (no drift);
  * `needs` ⊆ bootstrap-provided outputs;
  * enum fields valid (vpc/timeout_class/parallel/status);
  * `depends_on` references existing scenarios;
  * excluded entries carry an `exclude_reason`.
Exit non-zero on any violation. Run: python scripts/validate_registry.py
"""
from __future__ import annotations
import os, sys
try:
    import yaml
except ImportError:
    sys.exit("pip install pyyaml")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCEN = os.path.join(ROOT, "scenarios")
BOOTSTRAP_VARS = {
    "vpc_id", "subnet_id", "security_group_id", "security_group_id_list",
    "publicip_id", "ip_id", "ip_address", "keypair_name", "image_id",
    "server_type_id", "volume_id", "kubernetes_version",
}
VPC = {"none", "pool", "self"}
TIMEOUT = {"fast", "slow"}
PARALLEL = {"low", "normal"}
STATUS = {"green", "broken", "untested", "excluded"}


def main() -> int:
    reg = yaml.safe_load(open(os.path.join(ROOT, "coverage", "registry.yaml")))
    dirs = {d for d in os.listdir(SCEN) if os.path.isdir(os.path.join(SCEN, d))}
    errs = []

    for missing in sorted(dirs - set(reg)):
        errs.append(f"scenario dir '{missing}' has no registry entry")
    for extra in sorted(set(reg) - dirs):
        errs.append(f"registry entry '{extra}' has no scenarios/ dir")

    for name, e in reg.items():
        if not isinstance(e, dict):
            errs.append(f"{name}: entry is not a mapping"); continue
        if e.get("vpc") not in VPC:
            errs.append(f"{name}: vpc={e.get('vpc')!r} not in {sorted(VPC)}")
        if e.get("timeout_class") not in TIMEOUT:
            errs.append(f"{name}: timeout_class={e.get('timeout_class')!r}")
        if e.get("parallel") not in PARALLEL:
            errs.append(f"{name}: parallel={e.get('parallel')!r}")
        if e.get("status") not in STATUS:
            errs.append(f"{name}: status={e.get('status')!r}")
        for v in e.get("needs", []) or []:
            if v not in BOOTSTRAP_VARS:
                errs.append(f"{name}: needs '{v}' is not a bootstrap output {sorted(BOOTSTRAP_VARS)}")
        for dep in e.get("depends_on", []) or []:
            if dep not in reg:
                errs.append(f"{name}: depends_on '{dep}' is not a known scenario")
        if e.get("status") == "excluded" and not e.get("exclude_reason"):
            errs.append(f"{name}: excluded but no exclude_reason")
        # a pool/self scenario with no needs and vpc!=self is suspicious but allowed

    if errs:
        print("registry validation FAILED:")
        for x in errs:
            print("  -", x)
        return 1
    print(f"registry OK: {len(reg)} scenarios, all consistent")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
