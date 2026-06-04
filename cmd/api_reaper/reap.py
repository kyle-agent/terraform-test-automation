#!/usr/bin/env python3
"""Reap leaked VPCs (by name) + their dependency tree, via the SCP Open API.

terraform can't delete these (provider has no ImportState, #81). This deletes the
target VPCs and everything pinning them, scoped strictly by `vpc_id` match so it
NEVER touches live resources from other runs. Runs in CI (api-reaper.yml) reusing
the kyle-agent/api-test-automation framework (HMAC signer) on PYTHONPATH.

Set TARGET_VPC_NAMES to the leaked VPC names. Dependency order:
  ske clusters (nodepools->cluster) -> tgw vpc-connections (+ the test TGW) ->
  ports -> subnets -> internet-gateways -> the VPC (409-retry).
Requires SCP_ALLOW_MUTATIONS=true and SCP_ALLOW_DESTRUCTIVE=true.
"""
from __future__ import annotations

import time

from framework.client import ApiClient, MutationBlocked
from framework.config import settings

TARGET_VPC_NAMES = ["rpv269469061591", "rpv269469061593"]
# TGWs to delete explicitly by name (orphans whose vpc-connection may already be
# gone, so they wouldn't be caught by the per-vpc connection sweep below).
TARGET_TGW_NAMES = ["regr-tgwrb9377e"]


def items(body):
    if isinstance(body, dict):
        for v in body.values():
            if isinstance(v, list) and (not v or isinstance(v[0], dict)):
                return v
    return body if isinstance(body, list) else []


def get(c, svc, path):
    try:
        r = c.get(path, service=svc)
        return r.status, (items(r.body) if 200 <= r.status < 300 else [])
    except Exception as exc:
        print(f"  GET {svc}{path} error: {exc}")
        return 0, []


def delete(c, svc, path, json=None):
    try:
        r = c.delete(path, service=svc, json=json)
        print(f"  DELETE {svc}{path} -> {r.status}")
        return r.status
    except MutationBlocked as exc:
        print(f"  blocked: {exc}"); return None
    except Exception as exc:
        print(f"  DELETE {svc}{path} error: {exc}"); return None


def wait_gone(c, svc, path, timeout=300, interval=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        st, _ = get(c, svc, path)
        if st == 404:
            return True
        time.sleep(interval)
    return False


def reap_tgw(c, tgwid, tgwname=None):
    """Tear down a transit gateway in the REQUIRED order:
    routing-rules + uplink-routing-rules -> firewalls -> vpc-connections -> TGW.
    (A TGW won't delete while rules or connections remain — learned the hard way.)"""
    print(f"  reaping TGW {tgwname} ({tgwid})")
    for sub in ("routing-rules", "uplink-routing-rules"):
        _, rules = get(c, "vpc", f"/v1/transit-gateways/{tgwid}/{sub}")
        for r in rules:
            if r.get("id"):
                delete(c, "vpc", f"/v1/transit-gateways/{tgwid}/{sub}/{r['id']}")
    _, fws = get(c, "vpc", f"/v1/transit-gateways/{tgwid}/firewalls")
    for fw in fws:
        if fw.get("id"):
            delete(c, "vpc", f"/v1/transit-gateways/{tgwid}/firewalls/{fw['id']}")
    _, conns = get(c, "vpc", f"/v1/transit-gateways/{tgwid}/vpc-connections")
    for conn in conns:
        if conn.get("id"):
            delete(c, "vpc", f"/v1/transit-gateways/{tgwid}/vpc-connections/{conn['id']}")
            wait_gone(c, "vpc", f"/v1/transit-gateways/{tgwid}/vpc-connections/{conn['id']}", 240, 15)
    for _ in range(6):
        st = delete(c, "vpc", f"/v1/transit-gateways/{tgwid}")
        if st in (200, 202, 204, 404):
            wait_gone(c, "vpc", f"/v1/transit-gateways/{tgwid}", 240, 15); return
        if st == 409:
            time.sleep(15); continue
        return


def reap_vpc(c, vid, vname):
    print(f"== reaping {vname} ({vid}) ==")

    # subnets of this vpc (used to also match ske clusters by subnet)
    _, subnets = get(c, "vpc", "/v1/subnets")
    my_subnets = [s["id"] for s in subnets if str(s.get("vpc_id")) == vid and s.get("id")]

    # 1. ske clusters in this vpc/subnet -> nodepools then cluster
    _, ske = get(c, "ske", "/v1/clusters")
    for cl in ske:
        if str(cl.get("vpc_id")) == vid or str(cl.get("subnet_id")) in my_subnets:
            cid = cl.get("id")
            print(f"  ske cluster {cl.get('name')} ({cid}) pins this vpc")
            _, nps = get(c, "ske", f"/v1/clusters/{cid}/nodepools")
            for np in nps:
                if np.get("id"):
                    delete(c, "ske", f"/v1/nodepools/{np['id']}")
                    wait_gone(c, "ske", f"/v1/nodepools/{np['id']}", 600, 30)
            for _ in range(8):
                st = delete(c, "ske", f"/v1/clusters/{cid}")
                if st in (200, 202, 204, 404):
                    wait_gone(c, "ske", f"/v1/clusters/{cid}", 600, 30); break
                if st in (409, 500):
                    time.sleep(30); continue
                break

    # 2. transit-gateways connected to this vpc. A test TGW gets a FULL teardown
    # (rules -> connections -> tgw); a non-test TGW only loses this vpc's connection.
    _, tgws = get(c, "vpc", "/v1/transit-gateways")
    for tgw in tgws:
        tgwid = tgw.get("id")
        if not tgwid:
            continue
        _, conns = get(c, "vpc", f"/v1/transit-gateways/{tgwid}/vpc-connections")
        if not any(str(conn.get("vpc_id")) == vid for conn in conns):
            continue
        if str(tgw.get("name", "")).startswith("regr"):
            reap_tgw(c, tgwid, tgw.get("name"))
        else:
            for conn in conns:
                if str(conn.get("vpc_id")) == vid and conn.get("id"):
                    delete(c, "vpc", f"/v1/transit-gateways/{tgwid}/vpc-connections/{conn['id']}")
                    wait_gone(c, "vpc", f"/v1/transit-gateways/{tgwid}/vpc-connections/{conn['id']}", 240, 15)

    # 3. ports in this vpc
    _, ports = get(c, "vpc", "/v1/ports")
    for p in ports:
        if str(p.get("vpc_id")) == vid and p.get("id"):
            delete(c, "vpc", f"/v1/ports/{p['id']}")

    # 4. subnets
    for sid in my_subnets:
        delete(c, "vpc", f"/v1/subnets/{sid}")
        wait_gone(c, "vpc", f"/v1/subnets/{sid}")

    # 5. internet gateways in this vpc
    _, igws = get(c, "vpc", "/v1/internet-gateways")
    for ig in igws:
        if str(ig.get("vpc_id")) == vid and ig.get("id"):
            delete(c, "vpc", f"/v1/internet-gateways/{ig['id']}")
            wait_gone(c, "vpc", f"/v1/internet-gateways/{ig['id']}", 240, 15)

    # 6. the VPC, retrying 409 while children clear
    for attempt in range(6):
        st = delete(c, "vpc", f"/v1/vpcs/{vid}")
        if st in (200, 202, 204, 404):
            wait_gone(c, "vpc", f"/v1/vpcs/{vid}")
            return
        if st == 409:
            print(f"  vpc {vname} 409 (child remains) — retry {attempt+1}/6")
            time.sleep(15); continue
        return


def main() -> int:
    settings.require_credentials()
    c = ApiClient(settings)
    print(f"region={settings.region} env={settings.env_code}")
    _, vpcs = get(c, "vpc", "/v1/vpcs")
    targets = {v["id"]: v.get("name") for v in vpcs
               if v.get("name") in TARGET_VPC_NAMES and v.get("id")}
    print(f"all test vpcs present: {[v.get('name') for v in vpcs if str(v.get('name','')).startswith(('rpv','regr'))]}")
    print(f"targets resolved: {targets}")
    if not targets:
        print("no target VPCs found (already gone?)")
        return 0
    for vid, vname in targets.items():
        reap_vpc(c, vid, vname)

    # explicit TGW-by-name cleanup (orphans / belt-and-suspenders)
    if TARGET_TGW_NAMES:
        _, tgws = get(c, "vpc", "/v1/transit-gateways")
        for tgw in tgws:
            if tgw.get("name") in TARGET_TGW_NAMES and tgw.get("id"):
                reap_tgw(c, tgw["id"], tgw.get("name"))

    print("api-reaper done")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
