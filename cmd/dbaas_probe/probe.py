#!/usr/bin/env python3
"""DBaaS value-confirmation probe — POST a canonical create body to the live API
and print the RAW response.

Why this exists: the terraform provider accepts any DBaaS cluster `plan` and then
`apply` fails with an opaque `400 value_error` that names no field (provider issue
#83). The provider swallows the response body. This probe POSTs the *proven-valid*
create body from kyle-agent/api-test-automation (`framework/api_bodies.json`)
directly to the Open API and prints the full status + body, so the exact offending
field is visible. Then we fix the terraform fixture (or, if the raw API accepts a
body the provider rejects, that isolates a provider-mapping bug).

It looks up the live, account-specific values the body needs:
  * dbaas_engine_version_id  <- GET <engine>/v1/engine-versions  (first non-EOS)
  * instance server_type_name <- GET <engine>/v1/server-types     (first)
  * subnet_id                <- env SUBNET_ID, else first vpc/v1/subnets
The cluster `name` is generated letters-only (`^[a-zA-Z]*$`, issue #83).

Created clusters are DELETEd again immediately (leak 0). Requires
SCP_ALLOW_MUTATIONS=true and SCP_ALLOW_DESTRUCTIVE=true. Reuses the
api-test-automation HMAC framework on PYTHONPATH (same as the api-reaper).

Usage:  python cmd/dbaas_probe/probe.py <engine> [more engines...]
        python cmd/dbaas_probe/probe.py mysql postgresql eventstreams
        python cmd/dbaas_probe/probe.py all
"""
from __future__ import annotations

import json
import os
import random
import string
import sys
import time

from framework.client import ApiClient, MutationBlocked
from framework.config import settings

# engine -> (service-host name, api_bodies.json create-body key)
ENGINES = {
    "mysql":        ("mysql",        "database/mysql/mysqlcreatecluster"),
    "postgresql":   ("postgresql",   "database/postgresql/postgresqlcreatecluster"),
    "mariadb":      ("mariadb",      "database/mariadb/mariadbcreatecluster"),
    "sqlserver":    ("sqlserver",    "database/sqlserver/sqlservercreatecluster"),
    "epas":         ("epas",         "database/epas/epascreatecluster"),
    "cachestore":   ("cachestore",   "database/cachestore/cachestorecreatecluster"),
    "searchengine": ("searchengine", "data-analytics/searchengine/searchenginecreatecluster"),
    "eventstreams": ("eventstreams", "data-analytics/eventstreams/eventstreamscreatecluster"),
}

BODIES_PATHS = [
    os.environ.get("API_BODIES", ""),
    "/tmp/apitest/framework/api_bodies.json",
    "/tmp/api-test-automation/framework/api_bodies.json",
]


def load_bodies() -> dict:
    for p in BODIES_PATHS:
        if p and os.path.exists(p):
            return json.load(open(p))
    raise SystemExit("api_bodies.json not found (set API_BODIES or clone api-test-automation)")


def items(body):
    if isinstance(body, dict):
        for v in body.values():
            if isinstance(v, list) and (not v or isinstance(v[0], dict)):
                return v
    return body if isinstance(body, list) else []


def get_items(c, svc, path):
    try:
        r = c.get(path, service=svc)
        return r.status, (items(r.body) if 200 <= r.status < 300 else []), r.body
    except Exception as exc:
        return 0, [], str(exc)


def lettername(prefix="rp", n=4):
    # letters only (^[a-zA-Z]*$, #83) and SHORT: DBaaS name/instance_name_prefix
    # have a small max_length (canonical examples: name<=9, prefix<=8). 15 chars
    # tripped "string longer than the max_length constraint".
    return prefix + "".join(random.choice(string.ascii_lowercase) for _ in range(n))


def fill(body, *, name, engine_version_id, subnet_id, server_type_name, service_ip=None):
    b = json.loads(json.dumps(body))  # deep copy
    b["name"] = name
    if "instance_name_prefix" in b:
        # keep the prefix even shorter than the name to stay under its max_length
        b["instance_name_prefix"] = name[:6]
    if "dbaas_engine_version_id" in b and engine_version_id:
        b["dbaas_engine_version_id"] = engine_version_id
    if "subnet_id" in b and subnet_id:
        b["subnet_id"] = subnet_id
    # init_config_option: the canonical template leaves the DB account fields
    # empty; a real create needs non-empty values, so fill them.
    if b.get("timezone") == "":
        b["timezone"] = "Asia/Seoul"
    ico = b.get("init_config_option")
    if isinstance(ico, dict):
        if ico.get("database_name") == "":
            ico["database_name"] = name + "db"
        if ico.get("database_user_name") == "":
            ico["database_user_name"] = name + "adm"
        if ico.get("database_user_password") == "":
            ico["database_user_password"] = "Rp1234abcd!@"
        if ico.get("audit_enabled") == "":
            ico["audit_enabled"] = False
        bo = ico.get("backup_option")
        if isinstance(bo, dict):
            if bo.get("retention_period_day") == "":
                bo["retention_period_day"] = "7"
            if bo.get("starting_time_hour") == "":
                bo["starting_time_hour"] = "2"
        # sqlserver: nested databases[].database_name must be non-empty
        for db in ico.get("databases", []) or []:
            if isinstance(db, dict) and db.get("database_name") == "":
                db["database_name"] = name + "db"
    for ig in b.get("instance_groups", []):
        if isinstance(ig, dict):
            if ig.get("role_type") == "":  # sqlserver template leaves it blank
                ig["role_type"] = "ACTIVE"
            if "server_type_name" in ig and server_type_name:
                ig["server_type_name"] = server_type_name
            # service_ip_address must sit inside the subnet CIDR; the canonical
            # 192.168.10.10/32 only works if the subnet happens to be 192.168.x.
            if service_ip is not None:  # "" => blank it (test API auto-assign)
                for inst in ig.get("instances", []):
                    if isinstance(inst, dict) and "service_ip_address" in inst:
                        inst["service_ip_address"] = service_ip
    return b


def probe(c, engine):
    svc, body_key = ENGINES[engine]
    bodies = load_bodies()
    if body_key not in bodies:
        print(f"[{engine}] no canonical body {body_key}"); return
    template = bodies[body_key]

    # 1. live engine version (first non end-of-service)
    st, evs, raw = get_items(c, svc, "/v1/engine-versions")
    ev_id = ""
    for v in evs:
        if not v.get("end_of_service"):
            ev_id = v.get("id") or v.get("dbaas_engine_version_id") or ""
            break
    if not ev_id and evs:
        ev_id = evs[0].get("id", "")
    print(f"[{engine}] engine-versions -> {st}, picked id={ev_id!r} ({len(evs)} available)")

    # 2. live server type (first)
    st, sts, raw = get_items(c, svc, "/v1/server-types")
    stype = ""
    if sts:
        stype = sts[0].get("name") or sts[0].get("server_type_name") or sts[0].get("id") or ""
    print(f"[{engine}] server-types  -> {st}, picked name={stype!r} ({len(sts)} available)")

    # 3. subnet (capture its CIDR so the instance service_ip sits inside it)
    subnet_id = os.environ.get("SUBNET_ID", "")
    cidr = ""
    st, subs, raw = get_items(c, "vpc", "/v1/subnets")
    chosen = None
    for s in subs:
        if subnet_id and s.get("id") == subnet_id:
            chosen = s; break
    if chosen is None and subs and not subnet_id:
        chosen = subs[0]
    if chosen:
        subnet_id = chosen.get("id", subnet_id)
        cidr = chosen.get("cidr") or chosen.get("cidr_block") or chosen.get("subnet_cidr") or ""
    print(f"[{engine}] subnets       -> {st}, picked id={subnet_id!r} cidr={cidr!r} ({len(subs)} available)")

    service_ip = None
    if cidr:
        try:
            import ipaddress
            net = ipaddress.ip_network(cidr, strict=False)
            hosts = list(net.hosts())
            # low IPs (.1-.10) are reserved/in-use ("X is not available"); pick a
            # random host from the upper half to avoid collisions on a shared subnet.
            pool = hosts[len(hosts) // 2:] or hosts
            service_ip = f"{random.choice(pool)}/32"
        except Exception as exc:
            print(f"[{engine}] cidr parse failed ({exc}); using template service_ip")

    def post_once(sip, tag):
        name = lettername()
        payload = fill(template, name=name, engine_version_id=ev_id, subnet_id=subnet_id,
                       server_type_name=stype, service_ip=sip)
        print(f"[{engine}] POST /v1/clusters name={name} ({tag}) service_ip={sip!r}")
        try:
            r = c.post("/v1/clusters", service=svc, json=payload)
            body = r.body if isinstance(r.body, str) else json.dumps(r.body, ensure_ascii=False)
            print(f"[{engine}] >>> STATUS {r.status}  BODY {body}")
            cid = None
            if isinstance(r.body, dict):
                cid = (r.body.get("id") or (r.body.get("cluster") or {}).get("id")
                       or (r.body.get("resource") or {}).get("id"))  # 202: {"resource":{"id":...}}
            if cid and 200 <= r.status < 300:
                print(f"[{engine}] *** CREATED {cid} — values VALID — deleting for leak-0 ***")
                delete_cluster(c, svc, cid)
            return r.status, body
        except MutationBlocked as exc:
            print(f"[{engine}] blocked: {exc}"); return None, ""
        except Exception as exc:
            print(f"[{engine}] POST error: {exc}"); return 0, str(exc)

    st, body = post_once(service_ip, "forced-ip")
    # If the only complaint is the IP not being free on this shared subnet, retry
    # with service_ip blanked — proves whether the API auto-assigns (our terraform
    # fixtures omit service_ip_address, so this is the path that matters).
    if body and "is not available" in body:
        print(f"[{engine}] IP not free on shared subnet — retrying with blank service_ip (auto-assign?)")
        post_once("", "blank-ip")
    print("-" * 70)


# DBaaS clusters created by probe runs that leaked (202 id is under resource.id,
# which the first cleanup code missed). `probe.py cleanup` removes these by id.
LEAKED_IDS = {
    "mysql":      ["adce924e8eca4ae5884de311f3ef12d4"],
    "postgresql": ["eaadb833bc634cb5807269edee3408df"],
    "mariadb":    ["d5929f06bd814c53a785bd1526fdaab6"],
    "epas":       ["0944e0082bd4413898619a6c7601f4a9"],
    "cachestore": ["c116a8c5cd0245659098647180ff9cf2"],
}
# states from which a DBaaS cluster can be deleted (CREATING usually can't)
DELETABLE = {"RUNNING", "ACTIVE", "AVAILABLE", "STOPPED", "ERROR", "FAILED"}


def cluster_state(c, svc, cid):
    try:
        r = c.get(f"/v1/clusters/{cid}", service=svc)
        if r.status == 404:
            return "GONE"
        b = r.body if isinstance(r.body, dict) else {}
        cl = b.get("cluster") if isinstance(b.get("cluster"), dict) else b
        return str(cl.get("state") or cl.get("status") or "?")
    except Exception as exc:
        return f"ERR:{exc}"


def delete_cluster(c, svc, cid, timeout=1500, interval=30):
    """Delete a DBaaS cluster, waiting out CREATING until it's in a deletable state."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        st = cluster_state(c, svc, cid)
        if st == "GONE":
            print(f"  [{svc}] {cid} gone"); return True
        if st in DELETABLE or st == "?":
            try:
                r = c.delete(f"/v1/clusters/{cid}", service=svc)
                print(f"  [{svc}] DELETE {cid} (state={st}) -> {r.status}")
                if r.status in (200, 202, 204, 404):
                    if wait_gone(c, svc, cid):
                        return True
            except Exception as exc:
                print(f"  [{svc}] DELETE {cid} error: {exc}")
        else:
            print(f"  [{svc}] {cid} state={st} not yet deletable; waiting")
        time.sleep(interval)
    print(f"  [{svc}] {cid} still present after {timeout}s"); return False


def wait_gone(c, svc, cid, timeout=300, interval=20):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if cluster_state(c, svc, cid) == "GONE":
            return True
        time.sleep(interval)
    return False


def cleanup(c):
    print("== DBaaS leak cleanup (by id) ==")
    ok = True
    for svc, ids in LEAKED_IDS.items():
        for cid in ids:
            ok = delete_cluster(c, svc, cid) and ok
    print("cleanup done" if ok else "cleanup incomplete (some clusters remain)")
    return 0


def main(argv):
    settings.require_credentials()
    c = ApiClient(settings)
    print(f"region={settings.region} env={settings.env_code}")
    args = argv or ["mysql"]
    if args[0] == "cleanup":
        return cleanup(c)
    if args == ["all"]:
        args = list(ENGINES)
    for engine in args:
        if engine not in ENGINES:
            print(f"unknown engine {engine}; known: {', '.join(ENGINES)}"); continue
        probe(c, engine)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
