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
    for ig in b.get("instance_groups", []):
        if isinstance(ig, dict):
            if "server_type_name" in ig and server_type_name:
                ig["server_type_name"] = server_type_name
            # service_ip_address must sit inside the subnet CIDR; the canonical
            # 192.168.10.10/32 only works if the subnet happens to be 192.168.x.
            if service_ip:
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
            host = list(net.hosts())[9] if net.num_addresses > 12 else net.network_address + 1
            service_ip = f"{host}/32"
        except Exception as exc:
            print(f"[{engine}] cidr parse failed ({exc}); using template service_ip")

    name = lettername()
    payload = fill(template, name=name, engine_version_id=ev_id, subnet_id=subnet_id,
                   server_type_name=stype, service_ip=service_ip)
    print(f"[{engine}] POST /v1/clusters name={name}")
    print(f"[{engine}] payload={json.dumps(payload, ensure_ascii=False)}")
    try:
        r = c.post("/v1/clusters", service=svc, json=payload)
        print(f"[{engine}] >>> STATUS {r.status}")
        print(f"[{engine}] >>> BODY   {json.dumps(r.body, ensure_ascii=False) if not isinstance(r.body, str) else r.body}")
        # cleanup if it actually created something
        cid = None
        if isinstance(r.body, dict):
            cid = r.body.get("id") or (r.body.get("cluster") or {}).get("id")
        if cid and 200 <= r.status < 300:
            print(f"[{engine}] created {cid} — deleting for leak-0")
            time.sleep(5)
            try:
                d = c.delete(f"/v1/clusters/{cid}", service=svc)
                print(f"[{engine}] DELETE -> {d.status}")
            except Exception as exc:
                print(f"[{engine}] DELETE error: {exc}")
    except MutationBlocked as exc:
        print(f"[{engine}] blocked: {exc}")
    except Exception as exc:
        print(f"[{engine}] POST error: {exc}")
    print("-" * 70)


def main(argv):
    settings.require_credentials()
    c = ApiClient(settings)
    print(f"region={settings.region} env={settings.env_code}")
    args = argv or ["mysql"]
    if args == ["all"]:
        args = list(ENGINES)
    for engine in args:
        if engine not in ENGINES:
            print(f"unknown engine {engine}; known: {', '.join(ENGINES)}"); continue
        probe(c, engine)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
