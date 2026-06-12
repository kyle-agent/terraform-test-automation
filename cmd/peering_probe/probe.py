#!/usr/bin/env python3
"""VPC-peering create probe — bisect provider issue #61.

terraform vpc_vpc_peering create gets 400 "no value given for required property
approver_vpc_name ... Invalid error data" even though the provider provably puts
approver_vpc_name in the body. Meanwhile the sister API suite created a peering
(202) WITHOUT approver_vpc_name. So something else about the provider's request
shape/headers trips the server. This probe creates two tiny VPCs and POSTs
/v1/vpc-peerings with labeled body/header variants spanning the differences:

  provider SDK (library/vpc/1.1) request, from vendored ToMap() + vpc.go:
    {"approver_vpc_account_id": .., "approver_vpc_id": .., "approver_vpc_name": ..,
     "description": null, "name": .., "requester_vpc_id": ..}        # tags OMITTED
    header Scp-API-Version: "vpc 1.1"
    (description is ALWAYS sent — NewNullableString marks it set even when nil ->
     literal null; convertToTags returns nil for {} so tags is omitted, never [])
  api-suite request (proven 202):
    {"requester_vpc_id": .., "approver_vpc_id": .., "approver_vpc_account_id": ..,
     "name": .., "description": "..", "tags": []}                    # no approver_vpc_name
    NO Scp-API-Version header

Every 2xx-created peering is deleted again immediately (delete 400s while
CREATING -> retry; if it keeps refusing, approve {"type":"CREATE_APPROVE"} then
delete). 'cleanup' mode removes any prbpeer*/regrpeer-probe* peerings and the
prbpeera/prbpeerb VPCs. EXPECTED_ACCOUNT_ID guard like the reaper. Reuses the
reaper's stdlib HMAC client (cmd/api_reaper/_client.py).

Usage:  python cmd/peering_probe/probe.py [probe|cleanup]
"""
from __future__ import annotations

import json
import os
import random
import string
import sys
import time
import urllib.error
import urllib.request

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "api_reaper"))
import _client
from _client import ApiClient, settings

VPCS = [("prbpeera", "10.130.0.0/20"), ("prbpeerb", "10.141.0.0/20")]
PEER_PREFIXES = ("prbpeer", "regrpeer-probe")
SDK_HEADER = {"Scp-API-Version": "vpc 1.1"}  # library/vpc/1.1 api_vpc_v1_vpc_peering_api.go


def items(body):
    if isinstance(body, dict):
        for v in body.values():
            if isinstance(v, list) and (not v or isinstance(v[0], dict)):
                return v
    return body if isinstance(body, list) else []


def post_raw(path, body, extra_headers=None):
    """POST with the reaper's HMAC signing plus optional extra headers
    (ApiClient._do can't add headers, and variant c/d need Scp-API-Version)."""
    url = _client._host("vpc") + path
    hdrs = _client._headers("POST", url)
    hdrs.update(extra_headers or {})
    # compact encoding like Go's json.Marshal (HMAC doesn't sign the body)
    data = json.dumps(body, separators=(",", ":")).encode()
    req = urllib.request.Request(url, data=data, method="POST", headers=hdrs)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return _client.Resp(r.status, r.read().decode("utf-8", "replace"))
    except urllib.error.HTTPError as e:
        return _client.Resp(e.code, e.read().decode("utf-8", "replace"))


# ---------------------------------------------------------------- account guard

def live_account_id(c):
    try:
        for it in items(c.get("/v1/vpcs", service="vpc").body):
            if isinstance(it, dict) and it.get("account_id"):
                return it["account_id"]
    except Exception:
        pass
    return ""


def guard(c):
    """Refuse to CREATE resources unless the live account matches EXPECTED_ACCOUNT_ID
    (the access-key secret decides the account — same rationale as the reaper)."""
    exp = os.environ.get("EXPECTED_ACCOUNT_ID", "").strip()
    live = live_account_id(c)
    print(f"live account = {live or 'unknown/empty'}; EXPECTED_ACCOUNT_ID = {exp or 'unset'}")
    if not exp:
        raise SystemExit("GUARD: EXPECTED_ACCOUNT_ID unset -> refusing to create resources")
    if live and live != exp:
        raise SystemExit(f"GUARD: live account {live} != EXPECTED {exp} -> aborting")
    return exp


# ------------------------------------------------------------------------ VPCs

def vpc_state(c, vid):
    r = c.get(f"/v1/vpcs/{vid}", service="vpc")
    if r.status == 404:
        return "GONE"
    b = r.body.get("vpc") if isinstance(r.body, dict) and isinstance(r.body.get("vpc"), dict) else r.body
    return str((b or {}).get("state") or (b or {}).get("status") or "?")


def find_vpc(c, name):
    for v in items(c.get("/v1/vpcs", service="vpc").body):
        if v.get("name") == name:
            return v
    return None


def ensure_vpc(c, name, cidr):
    v = find_vpc(c, name)
    if v:
        print(f"[vpc] reusing {name} id={v.get('id')} state={v.get('state')}")
    else:
        r = c.post("/v1/vpcs", service="vpc", json={"name": name, "cidr": cidr, "tags": []})
        print(f"[vpc] POST /v1/vpcs name={name} cidr={cidr} -> {r.status} {r.text[:300]}")
        if not (200 <= r.status < 300):
            raise SystemExit(f"[vpc] create {name} failed ({r.status}); aborting probe")
        rb = r.body if isinstance(r.body, dict) else {}
        b = rb.get("vpc") if isinstance(rb.get("vpc"), dict) else rb
        v = b if b.get("id") else (b.get("resource") or {})
        if not v.get("id"):
            v = find_vpc(c, name) or {}
    if not v.get("id"):
        raise SystemExit(f"[vpc] cannot determine id of {name}")
    deadline = time.monotonic() + 300
    while time.monotonic() < deadline:
        st = vpc_state(c, v["id"])
        if st == "ACTIVE":
            break
        print(f"[vpc] {name} state={st}; waiting"); time.sleep(10)
    else:
        raise SystemExit(f"[vpc] {name} not ACTIVE in time")
    v = find_vpc(c, name) or v  # refresh (account_id etc.)
    print(f"[vpc] {name} ACTIVE id={v['id']} account_id={v.get('account_id')}")
    return v


def delete_vpc(c, v):
    """DELETE a VPC, backing off through 409/400 (peering teardown may lag)."""
    vid, name = v.get("id"), v.get("name")
    for i in range(12):
        r = c.delete(f"/v1/vpcs/{vid}", service="vpc")
        print(f"[cleanup] DELETE vpc {name} ({vid}) -> {r.status} {r.text[:200]}")
        if r.status in (200, 202, 204, 404):
            return True
        if r.status not in (400, 409):
            return False
        time.sleep(min(10 * (i + 1), 60))
    return False


# -------------------------------------------------------------------- peerings

def peering_state(c, pid):
    r = c.get(f"/v1/vpc-peerings/{pid}", service="vpc")
    if r.status == 404:
        return "GONE"
    b = r.body.get("vpc_peering") if isinstance(r.body, dict) and isinstance(r.body.get("vpc_peering"), dict) else r.body
    return str((b or {}).get("state") or "?")


def delete_peering(c, pid, timeout=900, interval=15):
    """Delete a peering. DELETE 400s while CREATING -> retry; if it keeps
    refusing, approve ({"type":"CREATE_APPROVE"}, itself 400 while CREATING,
    retry until it lands) so the peering reaches ACTIVE and becomes deletable."""
    deadline = time.monotonic() + timeout
    refused = 0
    while time.monotonic() < deadline:
        st = peering_state(c, pid)
        if st == "GONE":
            print(f"  [peering] {pid} gone"); return True
        r = c.delete(f"/v1/vpc-peerings/{pid}", service="vpc")
        print(f"  [peering] DELETE {pid} (state={st}) -> {r.status} {r.text[:200]}")
        if r.status in (200, 202, 204, 404):
            end = time.monotonic() + 300
            while time.monotonic() < end:
                if peering_state(c, pid) == "GONE":
                    print(f"  [peering] {pid} gone"); return True
                time.sleep(10)
            return False
        refused += 1
        if refused >= 3:  # delete keeps 400ing -> approval likely required first
            a = c.put(f"/v1/vpc-peerings/{pid}/approval", service="vpc",
                      json={"type": "CREATE_APPROVE"})
            print(f"  [peering] APPROVE {pid} -> {a.status} {a.text[:200]}")
        time.sleep(interval)
    print(f"  [peering] {pid} still present after {timeout}s"); return False


def created_id(body):
    if not isinstance(body, dict):
        return None
    for k in ("vpc_peering", "resource"):
        if isinstance(body.get(k), dict) and body[k].get("id"):
            return body[k]["id"]
    return body.get("id")


# -------------------------------------------------------------------- variants

def peername(tag):
    return "prbpeer" + tag + "".join(random.choice(string.digits) for _ in range(4))


def build_variants(va, vb, acct):
    """(label, body, extra-headers). dict order is preserved by json.dumps, so each
    body replicates its source's field order; provider bodies are alphabetical
    (Go marshals map keys sorted)."""
    def suite(name):  # proven-202 api-test-automation shape
        return {"requester_vpc_id": va["id"], "approver_vpc_id": vb["id"],
                "approver_vpc_account_id": acct, "name": name,
                "description": "peering probe (issue #61)", "tags": []}

    def provider(name):  # SDK vpc/1.1 exact: description null, tags omitted
        return {"approver_vpc_account_id": acct, "approver_vpc_id": vb["id"],
                "approver_vpc_name": vb["name"], "description": None,
                "name": name, "requester_vpc_id": va["id"]}

    b = suite(peername("b")); b["approver_vpc_name"] = vb["name"]
    d = provider(peername("d")); d.pop("approver_vpc_name")
    f = provider(peername("f")); f.pop("description")
    return [
        ("a: api-suite shape (no approver_vpc_name), no Scp-API-Version header",
         suite(peername("a")), {}),
        ("b: api-suite shape + approver_vpc_name, no Scp-API-Version header", b, {}),
        ("c: provider/SDK exact shape (description null, tags omitted), header 'vpc 1.1'",
         provider(peername("c")), SDK_HEADER),
        ("d: provider shape MINUS approver_vpc_name, header 'vpc 1.1'", d, SDK_HEADER),
        ("e: provider shape, NO Scp-API-Version header (isolates the header)",
         provider(peername("e")), {}),
        ("f: provider shape MINUS description:null, header 'vpc 1.1' (isolates null)",
         f, SDK_HEADER),
    ]


def probe(c):
    acct_exp = guard(c)
    va = ensure_vpc(c, *VPCS[0])
    vb = ensure_vpc(c, *VPCS[1])
    acct = vb.get("account_id") or acct_exp
    results = []
    for label, body, hdrs in build_variants(va, vb, acct):
        print("=" * 78)
        print(f"VARIANT {label}")
        print(f"  extra headers: {hdrs or '(none)'}")
        print(f"  request body : {json.dumps(body, separators=(',', ':'))}")
        try:
            r = post_raw("/v1/vpc-peerings", body, hdrs)
        except Exception as exc:
            print(f"  POST error: {exc}"); results.append((label, "ERR")); continue
        print(f"  >>> STATUS {r.status}  BODY {r.text}")
        results.append((label, r.status))
        pid = created_id(r.body) if 200 <= r.status < 300 else None
        if pid:
            print(f"  *** CREATED {pid} — deleting for leak-0 ***")
            delete_peering(c, pid)
    print("=" * 78)
    print("SUMMARY:")
    for label, st in results:
        print(f"  [{st}] {label}")
    return 0


# --------------------------------------------------------------------- cleanup

def cleanup(c):
    """Delete probe leftovers only: prbpeer*/regrpeer-probe* peerings, then the
    prbpeera/prbpeerb VPCs (exact names). Never touches anything else."""
    print("== peering-probe cleanup ==")
    ok = True
    for p in items(c.get("/v1/vpc-peerings", service="vpc").body):
        if str(p.get("name", "")).startswith(PEER_PREFIXES) and p.get("id"):
            print(f"[cleanup] peering {p['name']} ({p['id']}) state={p.get('state')}")
            ok = delete_peering(c, p["id"]) and ok
    names = {n for n, _ in VPCS}
    for v in items(c.get("/v1/vpcs", service="vpc").body):
        if v.get("name") in names and v.get("id"):
            ok = delete_vpc(c, v) and ok
    print("cleanup done" if ok else "cleanup incomplete (some resources remain)")
    return 0 if ok else 1


def main(argv):
    settings.require_credentials()
    c = ApiClient(settings)
    print(f"region={settings.region} env={settings.env_code}")
    mode = (argv[0] if argv else "probe").strip()
    if mode == "cleanup":
        return cleanup(c)
    if mode != "probe":
        raise SystemExit(f"unknown mode {mode!r}; use: probe | cleanup")
    return probe(c)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
