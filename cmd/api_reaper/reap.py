#!/usr/bin/env python3
"""Targeted leaked-resource reaper using the SCP Open API (HMAC auth).

Reuses the kyle-agent/api-test-automation framework (cloned alongside at runtime;
this file is run with that repo on PYTHONPATH) so we get its proven HMAC signer +
per-service host resolution. Deletes a FIXED list of leaked resources by id in
dependency order — never by name/prefix, so it can't touch live resources.

terraform can't delete these (the provider implements no ImportState anywhere,
issue #81); the Open API can, by id. Requires SCP_ALLOW_MUTATIONS=true and
SCP_ALLOW_DESTRUCTIVE=true (set by the workflow).

Paths verified against framework/api_catalog.json:
  vpc host: /v1/transit-gateways/{tgw}/vpc-connections/{conn}, /v1/transit-gateways/{tgw}, /v1/vpcs/{id}
  dns host: /v1/private-dns/{id}, /v1/public-domain-names/{id}
"""
from __future__ import annotations

import time

from framework.client import ApiClient, MutationBlocked
from framework.config import settings

TGW = "12af6b7e1d634e1aa574975c4090c43f"
CONN = "39ceadf32552426eb1929507823698cd"
VPC_A = "02bbf96c66d14dd297d3fe8a5fe1cb72"   # rpv269430906961
VPC_B = "8df00c61800d4ad9914cffb74d9a2149"   # rpv269430906962
PDNS = "42339727233a425eba6675d6428c90ff"    # regr-hz-pdnsfaa040
DOMAIN1 = "0ee424a4d97b4ff3b4a37691f7e245dd"  # regr.example.com
DOMAIN2 = "70b84eeaf98349d18bbb8d5141e09e07"  # regr.example.com


def delete(c, svc, path):
    try:
        r = c.delete(path, service=svc)
        print(f"  DELETE {svc}{path} -> {r.status}")
        return r.status
    except MutationBlocked as exc:
        print(f"  BLOCKED {svc}{path}: {exc}")
        return None
    except Exception as exc:
        print(f"  ERROR  {svc}{path}: {exc}")
        return None


def wait_gone(c, svc, path, timeout=300, interval=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            if c.get(path, service=svc).status == 404:
                print(f"  gone  {svc}{path}")
                return True
        except Exception:
            return True
        time.sleep(interval)
    print(f"  still-present after {timeout}s {svc}{path}")
    return False


def delete_vpc_with_retry(c, vid, label):
    for attempt in range(6):
        st = delete(c, "vpc", f"/v1/vpcs/{vid}")
        if st in (200, 202, 204, 404):
            wait_gone(c, "vpc", f"/v1/vpcs/{vid}")
            return st
        if st == 409:
            print(f"  vpc {label} 409 (child remains) — retry {attempt+1}/6 in 15s")
            time.sleep(15)
            continue
        return st
    return None


def main() -> int:
    settings.require_credentials()
    c = ApiClient(settings)
    print(f"region={settings.region} env={settings.env_code} "
          f"vpc-host={settings.resolve_base_url('vpc')} dns-host={settings.resolve_base_url('dns')}")

    # VPC A: connection -> tgw -> vpc
    delete(c, "vpc", f"/v1/transit-gateways/{TGW}/vpc-connections/{CONN}")
    wait_gone(c, "vpc", f"/v1/transit-gateways/{TGW}/vpc-connections/{CONN}", 240, 15)
    delete(c, "vpc", f"/v1/transit-gateways/{TGW}")
    wait_gone(c, "vpc", f"/v1/transit-gateways/{TGW}", 240, 15)
    delete_vpc_with_retry(c, VPC_A, "A/rpv269430906961")

    # VPC B: private-dns -> vpc
    delete(c, "dns", f"/v1/private-dns/{PDNS}")
    wait_gone(c, "dns", f"/v1/private-dns/{PDNS}", 240, 15)
    delete_vpc_with_retry(c, VPC_B, "B/rpv269430906962")

    # standalone public domain names
    delete(c, "dns", f"/v1/public-domain-names/{DOMAIN1}")
    delete(c, "dns", f"/v1/public-domain-names/{DOMAIN2}")

    print("api-reaper done")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
