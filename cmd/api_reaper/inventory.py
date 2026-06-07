#!/usr/bin/env python3
"""inventory.py -- READ-ONLY listing of what currently exists on the SCP account.

No deletes, ever. Walks the same endpoint set the reaper sweeps and prints every
resource's id / name / state, flagging the ones that match our test prefixes (likely
leaks) vs. others. Also lists OBS (S3) buckets. Run via .github/workflows/inventory.yml
(CI has the creds). Purpose: answer "what is still out there right now?".
"""
from __future__ import annotations

import os
import sys

from _client import ApiClient, settings

PREFIXES = ("regr", "rpv", "rps", "rpsg", "rpkp", "rpfs", "rske", "rlb", "rtgw",
            "igw_", "fw_igw", "IGW_", "FW_IGW")

# (service, path, label). Listed in rough dependency/topic order.
ENDPOINTS = [
    ("vpc", "/v1/vpcs", "VPC"),
    ("vpc", "/v1/subnets", "subnet"),
    ("vpc", "/v1/internet-gateways", "internet-gateway"),
    ("vpc", "/v1/nat-gateways", "nat-gateway"),
    ("vpc", "/v1/private-nats", "private-nat"),
    ("vpc", "/v1/publicips", "publicip"),
    ("vpc", "/v1/ports", "port"),
    ("vpc", "/v1/vpc-peerings", "vpc-peering"),
    ("vpc", "/v1/vpc-endpoints", "vpc-endpoint"),
    ("vpc", "/v1/transit-gateways", "transit-gateway"),
    ("security-group", "/v1/security-groups", "security-group"),
    ("vpn", "/v1/vpn-gateways", "vpn-gateway"),
    ("vpn", "/v1/vpn-tunnels", "vpn-tunnel"),
    ("virtualserver", "/v1/servers", "server"),
    ("virtualserver", "/v1/keypairs", "keypair"),
    ("filestorage", "/v1/volumes", "filestorage-volume"),
    ("ske", "/v1/clusters", "ske-cluster"),
    ("loadbalancer", "/v1/loadbalancers", "loadbalancer"),
    ("mysql", "/v1/clusters", "mysql-cluster"),
    ("postgresql", "/v1/clusters", "postgresql-cluster"),
    ("mariadb", "/v1/clusters", "mariadb-cluster"),
    ("sqlserver", "/v1/clusters", "sqlserver-cluster"),
    ("epas", "/v1/clusters", "epas-cluster"),
    ("vertica", "/v1/clusters", "vertica-cluster"),
    ("cachestore", "/v1/clusters", "cachestore-cluster"),
    ("searchengine", "/v1/clusters", "searchengine-cluster"),
    ("eventstreams", "/v1/clusters", "eventstreams-cluster"),
    ("dns", "/v1/private-dns", "private-dns"),
    ("dns", "/v1/public-domain-names", "public-domain-name"),
    ("dns", "/v1/hosted-zones", "hosted-zone"),
    ("resourcemanager", "/v1/resource-groups", "resource-group"),
    ("certificatemanager", "/v1/certificatemanager", "certificate"),
]


def items(body):
    if isinstance(body, dict):
        for v in body.values():
            if isinstance(v, list) and (not v or isinstance(v[0], dict)):
                return v
    return body if isinstance(body, list) else []


def name_of(it):
    for k in ("name", "volume_name", "cluster_name", "registry_name", "vpc_name"):
        if isinstance(it, dict) and it.get(k):
            return str(it[k])
    return ""


def is_test(name):
    n = (name or "").lower()
    return any(n.startswith(p.lower()) for p in PREFIXES)


def main():
    settings.require_credentials()
    c = ApiClient(settings)
    print(f"=== SCP inventory  region={settings.region} env={settings.env_code} ===")

    # Identity probe: which account does the access-key SECRET actually belong to?
    # (Independent of infra resources, so it works even on an empty account.) IAM
    # list endpoints are account-scoped and their items carry account_id; we also try
    # listing users for the configured SCP_ACCOUNT_ID to see if the secret matches it.
    cfg_acct = os.environ.get("SCP_ACCOUNT_ID", "").strip()
    id_accounts = set()
    for path in ("/v1/roles", "/v1/groups", "/v1/policies"):
        try:
            r = c.get(path, service="iam")
            for it in items(r.body):
                if isinstance(it, dict) and it.get("account_id"):
                    id_accounts.add(it["account_id"])
        except Exception:
            pass
    if cfg_acct:
        try:
            ru = c.get(f"/v1/accounts/{cfg_acct}/users", service="iam")
            print(f"--- identity: GET /v1/accounts/{cfg_acct}/users -> {ru.status} "
                  f"({'secret CAN see this account' if getattr(ru,'ok',False) else 'secret is NOT this account'})")
        except Exception as exc:
            print(f"--- identity: account-users probe error: {exc}")
    print(f"--- identity: account(s) from IAM = {sorted(id_accounts) or 'unknown'} ---")

    total = test_total = 0
    accounts = set()
    for svc, path, label in ENDPOINTS:
        try:
            r = c.get(path, service=svc)
        except Exception as exc:
            print(f"[{label}] list error: {exc}")
            continue
        if not getattr(r, "ok", False):
            # 403/404 are common for services not enabled on the account; note briefly.
            print(f"[{label}] {svc}{path} -> {r.status}")
            continue
        rows = items(r.body)
        if not rows:
            continue
        print(f"[{label}] {len(rows)} found:")
        for it in rows:
            if not isinstance(it, dict):
                continue
            rid = it.get("id") or it.get("volume_id") or it.get("name") or "?"
            nm = name_of(it)
            state = it.get("state") or it.get("status") or ""
            flag = "  <== TEST-PREFIX (likely leak)" if is_test(nm) else ""
            if it.get("account_id"):
                accounts.add(it["account_id"])
            print(f"    - id={rid} name={nm or '-'} state={state}{flag}")
            total += 1
            if is_test(nm):
                test_total += 1
    # Which account is the access-key SECRET actually hitting? (vs the SCP_ACCOUNT_ID var)
    print(f"=== live account(s) from resources: {sorted(accounts) or 'unknown/empty'} "
          f"| SCP_ACCOUNT_ID var = {os.environ.get('SCP_ACCOUNT_ID', 'unset')} ===")
    print(f"=== totals: {total} resource(s) listed, {test_total} match test prefixes ===")

    # OBS buckets (S3-compatible) for completeness.
    try:
        import boto3
        from botocore.config import Config
        ak = os.environ.get("TF_VAR_obs_access_key") or os.environ.get("OBS_ACCESS_KEY")
        sk = os.environ.get("TF_VAR_obs_secret_key") or os.environ.get("OBS_SECRET_KEY")
        ep = os.environ.get("TF_VAR_obs_endpoint", "https://object-store.kr-west1.e.samsungsdscloud.com")
        if ak and sk:
            s3 = boto3.client("s3", endpoint_url=ep, aws_access_key_id=ak,
                              aws_secret_access_key=sk, region_name="us-east-1",
                              config=Config(s3={"addressing_style": "path"}))
            buckets = s3.list_buckets().get("Buckets", [])
            print(f"=== OBS buckets: {len(buckets)} ===")
            for b in buckets:
                print(f"    - {b['Name']} (created {b.get('CreationDate')})")
        else:
            print("=== OBS buckets: skipped (no creds) ===")
    except Exception as exc:
        print(f"=== OBS buckets: error {exc} ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())

# refresh 2026-06-07T10:09:52Z

# verify-empty 2026-06-07T12:42:16Z

# final verify after retiring main schedules 2026-06-07T13:21:52Z
