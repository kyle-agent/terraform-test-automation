#!/usr/bin/env python3
"""gen_ds_smoke.py - generate the data-source read-smoke layer from provider source.

Scans the provider checkout (samsungcloudplatform/service/**) and emits:

  * coverage/provider_surface.json - the authoritative provider surface, split by
    kind: {"resources": {type: {family}}, "datasources": {type: {family, required,
    scenario | excluded+reason}}}. 59 type names exist as BOTH a resource and a
    (singular) data source; they are separate code paths and appear in both maps.
    Per-data-source disposition:
      scenario: ds_<service>  -> read-verified by that smoke scenario
      excluded: true + reason -> not standalone-readable
  * scenarios/ds_<service>/main.tf - one read-only smoke scenario per service
    family: a bare `data` block per standalone-readable data source (list
    endpoints take only optional filters). No resources are created; the
    capability pipeline exercises the reads at plan time.

A data source is standalone-readable when its schema has no Required attribute,
or every Required attribute has a documented constant (CONST_ARGS).

Required-argument detection: the authoritative source is `terraform providers
schema -json` (it follows delegated `resp.Schema = XxxSchema()` indirection that
a regex cannot). Pass that dump with --schema to use it; without it the script
falls back to a best-effort regex scan of the schema literals (which misses the
handful of data sources whose schema is built by a helper function). The service
-> family grouping always comes from the source-tree directory layout.

Usage:
  python3 scripts/gen_ds_smoke.py [provider-checkout] [--schema provider_schema.json]

Produce the schema dump once (CI does this with the patched build):
  terraform providers schema -json > provider_schema.json
Rerun whenever the provider surface changes, then review `git diff`.
"""
from __future__ import annotations

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_PROVIDER = os.path.join(
    os.path.dirname(ROOT), "terraform-provider-samsungcloudplatformv2"
)
SURFACE_JSON = os.path.join(ROOT, "coverage", "provider_surface.json")
SCEN_DIR = os.path.join(ROOT, "scenarios")
PREFIX = "samsungcloudplatformv2_"

# Required args that a smoke read can satisfy with a documented constant
# (closed enum or documented example value in the provider schema).
CONST_ARGS = {
    "network_logging_network_logging_configurations": {
        "resource_type": '"SECURITY_GROUP"'  # OneOf(FIREWALL, SECURITY_GROUP, NAT)
    },
    "network_logging_network_logging_storages": {
        "resource_type": '"SECURITY_GROUP"'  # OneOf(FIREWALL, SECURITY_GROUP, NAT)
    },
    "ske_nodepool_images": {
        "scp_original_image_type": '"k8s"'  # documented: k8s | k8s_gpu
    },
}

# Provider service dir -> dashboard family (only where they differ).
DIR_FAMILY = {"baremetalblockstorage": "baremetal"}

# Schema-valid but NOT standalone-readable in practice — discovered by sweep run
# 27451961730 (the first ds_* discovery run, empty account). Three patterns:
_R404 = "bare read 404s on an empty account (show-by-id semantics; run 27451961730)"
_RLIST = "list 404s without its parent resource (run 27451961730)"
_RFILT = "API rejects unfiltered read: eventState is required (run 27451961730)"
_RFILT_PRID = "API rejects unfiltered read: productResourceId/eventPolicyId required (run 27452400061)"
RUNTIME_EXCLUDED = {
    "budget_budget": _R404,
    "cachestore_cluster": _R404,
    "certificate_manager": _R404,
    "cloudmonitoring_event": _R404,
    "cloudmonitoring_account_events": _RFILT,
    "dns_hosted_zone": _R404,
    "dns_private_dns": _R404,
    "epas_cluster": _R404,
    "eventstreams_cluster": _R404,
    "gslb_gslb": _R404,
    "iam_group": _R404,
    "iam_group_members": _RLIST,
    "loadbalancer_lb_certificate": _R404,
    "loadbalancer_lb_health_check": _R404,
    "mariadb_cluster": _R404,
    "mysql_cluster": _R404,
    "postgresql_cluster": _R404,
    "searchengine_cluster": _R404,
    "servicewatch_alert": _R404,
    "servicewatch_dashboard": _R404,
    "sqlserver_cluster": _R404,
    "vertica_cluster": _R404,
    "vpc_private_nat": _R404,
    "vpc_private_nat_ips": _RLIST,
    # second wave, sweep 27452400061 (offenders masked behind the first wave)
    "cloudmonitoring_event_policies": _RFILT_PRID,
    "cloudmonitoring_event_policy": _RFILT_PRID,
    "dns_public_domain_name": _R404,
    "dns_record": _R404,
    "iam_group_policy_bindings": _RLIST,
    "iam_policy": _R404,
    "loadbalancer_lb_listener": _R404,
    "loadbalancer_lb_member": _RLIST,
}


def snake(name):
    return re.sub(r"(?<!^)(?=[A-Z])", "_", name).lower()


def top_level_attrs(body):
    """[(attr_name, attr_block_src)] for depth-1 attrs of the FIRST
    `Attributes: map[string]schema.Attribute{...}` in a Schema body."""
    m = re.search(r"Attributes:\s*map\[string\]schema\.Attribute\{", body)
    if not m:
        return []
    key_re = re.compile(
        r'\s*(?:common\.ToSnakeCase\("([A-Za-z0-9]+)"\)|"([a-z0-9_]+)"):\s*'
    )
    attrs, depth, pos = [], 1, m.end()
    while pos < len(body) and depth > 0:
        if depth == 1:
            km = key_re.match(body, pos)
            if km:
                name = snake(km.group(1)) if km.group(1) else km.group(2)
                bpos = body.find("{", km.end())
                if bpos == -1:
                    break
                d2, p2 = 1, bpos + 1
                while p2 < len(body) and d2 > 0:
                    if body[p2] == "{":
                        d2 += 1
                    elif body[p2] == "}":
                        d2 -= 1
                    p2 += 1
                attrs.append((name, body[bpos:p2]))
                pos = p2
                continue
        ch = body[pos]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
        pos += 1
    return attrs


def required_attrs(body):
    """Top-level attrs marked Required (Required flags nested inside Computed
    response models are NOT requireds of the data source itself)."""
    req = []
    for name, block in top_level_attrs(body):
        depth = 0
        for m in re.finditer(r"\{|\}|(Required):\s*true", block):
            t = m.group(0)
            if t == "{":
                depth += 1
            elif t == "}":
                depth -= 1
            elif depth == 1:
                req.append(name)
                break
    return sorted(set(req))


def load_schema_required(schema_path):
    """{short_type: [required_attrs]} for data sources, from a terraform
    `providers schema -json` dump (authoritative). Returns None if unreadable."""
    try:
        data = json.load(open(schema_path, encoding="utf-8"))
    except (OSError, ValueError):
        return None
    schemas = data.get("provider_schemas", {})
    # single provider in the dump
    for _addr, ps in schemas.items():
        ds = ps.get("data_source_schemas", {})
        out = {}
        for t, block in ds.items():
            short = t[len(PREFIX):] if t.startswith(PREFIX) else t
            attrs = (block.get("block", {}) or {}).get("attributes", {}) or {}
            out[short] = sorted(k for k, a in attrs.items() if a.get("required"))
        return out
    return None


def scan(provider_root):
    svc = os.path.join(provider_root, "samsungcloudplatform", "service")
    resources, datasources = {}, {}
    for dirname in sorted(os.listdir(svc)):
        d = os.path.join(svc, dirname)
        if not os.path.isdir(d):
            continue
        family = DIR_FAMILY.get(dirname, dirname)
        for fn in sorted(os.listdir(d)):
            if not fn.endswith(".go"):
                continue
            src = open(os.path.join(d, fn), encoding="utf-8").read()
            types = re.findall(r'ProviderTypeName \+ "_([a-z_0-9]+)"', src)
            if not types:
                continue
            is_ds = "datasource.DataSource" in src
            is_res = re.search(r"\bresource\.Resource\b", src) is not None
            m = re.search(
                r"func \([^)]+\) Schema\([^)]*datasource\.SchemaResponse\) \{(.*?)(?:\nfunc |\Z)",
                src,
                re.S,
            )
            body = m.group(1) if m else ""
            for t in types:
                if is_res and not is_ds:
                    resources[t] = {"family": family}
                elif is_ds:
                    datasources[t] = {"family": family, "required": required_attrs(body)}
    return resources, datasources


def disposition(datasources):
    """Annotate each datasource entry in place with its test disposition."""
    for t, info in sorted(datasources.items()):
        req = [a for a in info["required"] if a not in CONST_ARGS.get(t, {})]
        if req:
            info["excluded"] = True
            info["reason"] = (
                "requires %s (parent-resource arg; not standalone-readable)"
                % ", ".join(req)
            )
        elif t in RUNTIME_EXCLUDED:
            info["excluded"] = True
            info["reason"] = RUNTIME_EXCLUDED[t]
        else:
            info["scenario"] = "ds_" + info["family"].replace("-", "_")
    return datasources


TF_HEADER = """terraform {
  required_version = ">= 1.6"
  required_providers {
    samsungcloudplatformv2 = {
      source  = "SamsungSDSCloud/samsungcloudplatformv2"
      version = ">= 0.0.1"
    }
  }
}

provider "samsungcloudplatformv2" {}

# Read-only data-source smoke fixture (generated by scripts/gen_ds_smoke.py).
# Creates NOTHING: each block exercises a list/read endpoint with no or
# constant-only arguments, so plan/apply verify the data-source code paths.
"""


def write_scenarios(disp):
    by_scen = {}
    for t, e in disp.items():
        if e.get("scenario"):
            by_scen.setdefault(e["scenario"], []).append(t)
    for scen, types in sorted(by_scen.items()):
        d = os.path.join(SCEN_DIR, scen)
        os.makedirs(d, exist_ok=True)
        blocks = []
        for t in sorted(types):
            args = CONST_ARGS.get(t, {})
            body = "".join("  %s = %s\n" % (k, v) for k, v in sorted(args.items()))
            blocks.append('data "%s%s" "smoke" {\n%s}\n' % (PREFIX, t, body))
        with open(os.path.join(d, "main.tf"), "w", encoding="utf-8") as fh:
            fh.write(TF_HEADER + "\n" + "\n".join(blocks))
    return sorted(by_scen)


def main():
    args = sys.argv[1:]
    schema_path = None
    if "--schema" in args:
        i = args.index("--schema")
        schema_path = args[i + 1]
        args = args[:i] + args[i + 2:]
    provider_root = args[0] if args else DEFAULT_PROVIDER
    if not os.path.isdir(os.path.join(provider_root, "samsungcloudplatform")):
        sys.exit("provider checkout not found at %s" % provider_root)

    resources, datasources = scan(provider_root)

    # Override regex requireds with the authoritative schema dump when provided.
    auth = load_schema_required(schema_path) if schema_path else None
    if auth is not None:
        for t, info in datasources.items():
            if t in auth:
                info["required"] = auth[t]
        print("using authoritative required-args from %s" % schema_path,
              file=sys.stderr)
    else:
        print("WARNING: no --schema dump; required-args from best-effort regex "
              "scan (may miss delegated-schema data sources)", file=sys.stderr)

    disp = disposition(datasources)
    surface = {
        "resources": {t: resources[t] for t in sorted(resources)},
        "datasources": {t: datasources[t] for t in sorted(datasources)},
    }
    os.makedirs(os.path.dirname(SURFACE_JSON), exist_ok=True)
    with open(SURFACE_JSON, "w", encoding="utf-8") as fh:
        json.dump(surface, fh, indent=1, sort_keys=True)
        fh.write("\n")

    scens = write_scenarios(disp)
    smoke = sum(1 for e in disp.values() if e.get("scenario"))
    excl = len(disp) - smoke
    print(
        "surface: %d resources, %d datasources | smoke %d, excluded %d | %d scenarios: %s"
        % (len(resources), len(datasources), smoke, excl, len(scens), " ".join(scens))
    )


if __name__ == "__main__":
    main()
