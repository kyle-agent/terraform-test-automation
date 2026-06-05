#!/usr/bin/env python3
"""One-time generator: build coverage/registry.yaml (the single source of truth)
from the existing sources — cost_tiers.yaml (cost/status/issues), the live
scenarios/*/main.tf (declared variables -> `needs`, self-VPC detection), and the
known lane membership currently hardcoded in coverage-sweep-pool.yml.

After this runs once, registry.yaml is the hand-edited source of truth; this
generator is kept only for reference/re-seeding. Run from repo root:
    python scripts/gen_registry.py > coverage/registry.yaml
"""
from __future__ import annotations
import os, re, sys, glob

try:
    import yaml
except ImportError:
    sys.exit("pip install pyyaml")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCEN = os.path.join(ROOT, "scenarios")

# Variables the bootstrap step provides (scenario `needs` = its declared vars ∩ this)
BOOTSTRAP_VARS = {
    "vpc_id", "subnet_id", "security_group_id", "security_group_id_list",
    "publicip_id", "ip_id", "ip_address", "keypair_name", "image_id",
    "server_type_id", "volume_id", "kubernetes_version",
}

# Current lane membership (verbatim from coverage-sweep-pool.yml) — preserved so
# behavior does not change for already-placed scenarios.
NOVPC = set("""iam_policy iam_group iam_group_member iam_group_policy_bindings iam_role
iam_role_policy_bindings iam_user iam_user_policy_bindings resourcemanager_resource_group
certificate_manager certificate_manager_self_sign servicewatch_dashboard servicewatch_event_rule
servicewatch_log_group servicewatch_log_stream servicewatch_alert loggingaudit_trail budget_budget
billing_planned_compute dns_hosted_zone dns_record""".split())
POOL_VPC1 = set("""vpc_port vpc_nat_gateway security_group_basic securitygroup_rule_basic
firewall_firewall_rule network_logging_network_logging_storage vpc_subnet vpc_cidr vpc_subnet_vip
vpc_subnet_vip_port vpc_subnet_vip_nat_ip""".split())
POOL_VPC2 = set("""virtualserver_keypair virtualserver_server virtualserver_server_group
virtualserver_volume virtualserver_image filestorage_volume filestorage_snapshot_schedule
filestorage_replication backup_backup directconnect_direct_connect directconnect_routing_rule
gslb_gslb""".split())
POOL_DBAAS = {"mysql_cluster", "postgresql_cluster", "mariadb_cluster", "epas_cluster",
              "cachestore_cluster", "sqlserver_cluster", "searchengine_cluster",
              "eventstreams_basic", "ske_cluster", "ske_nodepool"}
SELFVPC = {"vpn_vpn_gateway", "vpn_vpn_tunnel", "vpc_internet_gateway", "vpc_vpc_endpoint",
           "vpc_vpc_peering", "vpc_vpc_peering_approval", "vpc_vpc_peering_rule"}

# Provider-blocked / out-of-scope families -> excluded (kept in registry with reason)
EXCLUDE = {
    "cloudmonitoring_event_policy": "cloudmonitoring deprecated",
    "configinspection": "out of scope (per request)",
    "vertica_cluster": "out of scope (heavy)",
    "baremetal_baremetal": "out of scope (heavy)",
    "baremetal_blockstorage_volume": "out of scope (heavy)",
}
# loadbalancer family -> blocked by #77 (create no-wait -> destroy leak)
def is_lb(name): return name.startswith("loadbalancer_")
# transit-gateway family -> blocked by #76 (status-waiter hang)
def is_tgw(name): return name.startswith("vpc_transit_gateway")

SLOW = lambda n: n in POOL_DBAAS or n.endswith("_cluster") or n.endswith("_nodepool")
# scenarios that mutate the SHARED bootstrap VPC's CIDR/subnets -> keep low parallel
# within a shard to avoid CIDR contention (was the vpc1-shard @ MATRIX_PARALLEL 2).
LOW_PARALLEL = {"vpc_subnet", "vpc_cidr", "vpc_subnet_vip", "vpc_subnet_vip_port",
                "vpc_subnet_vip_nat_ip", "vpc_nat_gateway", "vpc_port"}


def scenario_vars(path):
    try:
        txt = open(path, encoding="utf-8").read()
    except OSError:
        return set(), False
    vars_ = set(re.findall(r'variable\s+"([^"]+)"', txt))
    makes_vpc = bool(re.search(r'resource\s+"samsungcloudplatformv2_vpc_vpc"', txt))
    return vars_, makes_vpc


def lane_for(name, declared, makes_vpc):
    if name in NOVPC:
        return "none"
    if name in SELFVPC:
        return "self"
    if name in POOL_VPC1 or name in POOL_VPC2 or name in POOL_DBAAS:
        return "pool"
    # inference for not-yet-placed scenarios
    if makes_vpc:
        return "self"
    if declared & BOOTSTRAP_VARS:
        return "pool"
    return "none"


def main():
    cost = yaml.safe_load(open(os.path.join(ROOT, "coverage", "cost_tiers.yaml")))
    dirs = sorted(d for d in os.listdir(SCEN) if os.path.isdir(os.path.join(SCEN, d)))
    out = {}
    for name in dirs:
        declared, makes_vpc = scenario_vars(os.path.join(SCEN, name, "main.tf"))
        c = cost.get(name, {}) or {}
        status = c.get("status", "untested")
        issues = c.get("issues", []) or []
        lane = lane_for(name, declared, makes_vpc)
        entry = {
            "family": name.split("_", 1)[0],
            "vpc": lane,                       # none | pool | self
            "timeout_class": "slow" if SLOW(name) else "fast",
            "parallel": "low" if name in LOW_PARALLEL else "normal",
            "needs": sorted(declared & BOOTSTRAP_VARS),
            "depends_on": [],
            "update": os.path.exists(os.path.join(SCEN, name, "update.tfvars")),
            "import": False,
            "cost": c.get("cost", "cheap"),
            "status": status,
            "issues": list(issues),
        }
        if name in EXCLUDE:
            entry["status"] = "excluded"; entry["exclude_reason"] = EXCLUDE[name]
        elif is_lb(name):
            entry["status"] = "excluded"; entry["exclude_reason"] = "provider #77 (LB destroy leak)"
        elif is_tgw(name):
            entry["status"] = "excluded"; entry["exclude_reason"] = "provider #76 (TGW status-waiter hang)"
        out[name] = entry

    hdr = ("# registry.yaml — SINGLE SOURCE OF TRUTH for test scenarios.\n"
           "# Generated once by scripts/gen_registry.py from cost_tiers.yaml + live\n"
           "# scenario HCL + workflow lane membership; hand-edited thereafter.\n"
           "# Consumed by: scripts/plan_matrix.py (workflow matrix), scripts/validate_registry.py,\n"
           "# the capability harness, and the dashboard.\n#\n"
           "# Fields: family, vpc(none|pool|self), timeout_class(fast|slow), parallel(low|normal),\n"
           "# needs(bootstrap outputs), depends_on(scenario names), update/import(stage opt-in), cost, status\n"
           "# (green|broken|untested|excluded), issues, [exclude_reason].\n")
    sys.stdout.write(hdr)
    sys.stdout.write(yaml.safe_dump(out, sort_keys=True, default_flow_style=False, width=100))


if __name__ == "__main__":
    main()
