#!/usr/bin/env python3
"""Derive the CI execution plan (lanes + pool shards) from coverage/registry.yaml.

Replaces the hand-maintained comma-strings in the workflow. Emits a JSON object:
  {
    "novpc":   "a,b,c",                         # vpc:none  -> single high-parallel job
    "selfvpc": "x,y",                           # vpc:self  -> single low-parallel job (each makes own VPC)
    "pool":    [ {label, scenarios, parallel} ] # vpc:pool  -> one bootstrap VPC per shard
  }

Pool sharding:
  * slow (cluster/nodepool) scenarios  -> one per shard, parallel 1 (each ~30m).
  * fast 'low' scenarios (CIDR mutators) -> grouped, parallel 2.
  * fast 'normal' scenarios            -> packed FAST_CAP per shard, parallel 4.

Selection (env, all optional):
  SELECT_STATUS  comma list (default 'green,broken,untested'  — excludes 'excluded')
  SELECT_VPC     comma list of lanes to include (default all)
  SELECT_FAMILY  comma list of families to include (default all)
  FAST_CAP       fast-normal scenarios per shard (default 8)

Usage:
  python scripts/plan_matrix.py            # prints the JSON plan
  python scripts/plan_matrix.py --github   # also writes novpc/selfvpc/pool to $GITHUB_OUTPUT
"""
from __future__ import annotations
import json, os, sys
try:
    import yaml
except ImportError:
    sys.exit("pip install pyyaml")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def env_set(name, default):
    v = os.environ.get(name, "").strip()
    return {x.strip() for x in v.split(",") if x.strip()} if v else set(default)


def chunk(xs, n):
    for i in range(0, len(xs), n):
        yield xs[i:i + n]


def build_plan():
    reg = yaml.safe_load(open(os.path.join(ROOT, "coverage", "registry.yaml")))
    sel_status = env_set("SELECT_STATUS", {"green", "broken", "untested"})
    sel_vpc = env_set("SELECT_VPC", {"none", "pool", "self"})
    sel_family = env_set("SELECT_FAMILY", set())  # empty => all
    fast_cap = int(os.environ.get("FAST_CAP", "8"))

    def included(e):
        if e.get("status") not in sel_status:
            return False
        if e.get("vpc") not in sel_vpc:
            return False
        if sel_family and e.get("family") not in sel_family:
            return False
        return True

    names = sorted(n for n, e in reg.items() if included(reg[n]))
    novpc, selfvpc, pool = [], [], []
    for n in names:
        e = reg[n]
        if e["vpc"] == "none":
            novpc.append(n)
        elif e["vpc"] == "self":
            selfvpc.append(n)
        else:
            pool.append(n)

    # pool sharding
    shards = []
    slow = [n for n in pool if reg[n]["timeout_class"] == "slow"]
    fast_low = [n for n in pool if reg[n]["timeout_class"] == "fast" and reg[n]["parallel"] == "low"]
    fast_norm = [n for n in pool if reg[n]["timeout_class"] == "fast" and reg[n]["parallel"] == "normal"]
    for n in slow:                                   # one VPC each
        shards.append({"label": n, "scenarios": n, "parallel": 1})
    for i, grp in enumerate(chunk(fast_low, fast_cap)):  # CIDR-contention -> parallel 2
        shards.append({"label": f"net-{i+1}", "scenarios": ",".join(grp), "parallel": 2})
    for i, grp in enumerate(chunk(fast_norm, fast_cap)):
        shards.append({"label": f"fast-{i+1}", "scenarios": ",".join(grp), "parallel": 4})

    return {"novpc": ",".join(novpc), "selfvpc": ",".join(selfvpc), "pool": shards}


def main(argv):
    plan = build_plan()
    print(json.dumps(plan, indent=2))
    if "--github" in argv and os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as fh:
            fh.write(f"novpc={plan['novpc']}\n")
            fh.write(f"selfvpc={plan['selfvpc']}\n")
            fh.write(f"pool={json.dumps(plan['pool'])}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
