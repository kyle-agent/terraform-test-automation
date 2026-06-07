#!/usr/bin/env python3
"""Self-contained Samsung Cloud Platform (SCP) Open API helper — HMAC auth.

Auxiliary to the main terraform test workflow. No external deps (stdlib only),
no Go SDK, no GH_ACCESS_TOKEN. Reproduces the auth proven by the
kyle-agent/api-test-automation framework:

  signing string = METHOD + encodeURI(full_url) + timestamp_ms + accessKey + clientType
  signature      = Base64( HMAC_SHA256(secretKey, signing_string) )
  headers        = Scp-Accesskey, Scp-Signature, Scp-Timestamp,
                   Scp-ClientType=Openapi, Accept-Language

Per-service hosts:
  regional: https://<service>.<region>.<env>.samsungsdscloud.com   (vpc, dns, virtualserver, ...)
  global  : https://<service>.<env>.samsungsdscloud.com            (iam, product, billing, ...)

Env: SCP_ACCESS_KEY, SCP_SECRET_KEY, SCP_REGION (e.g. kr-west1), SCP_ENV (e.g. e).
Destructive calls (delete) require SCP_ALLOW_DESTRUCTIVE=1 to avoid accidents.

Usage:
  scp_api.py get    <service> <path>                 # raw GET (prints status + body)
  scp_api.py exists <service> <path>                 # prints "EXISTS" (2xx) / "ABSENT" (404)
  scp_api.py list   <service> <path> [name_prefix]   # list items, optional name filter
  scp_api.py delete <service> <path>                 # DELETE by id (needs SCP_ALLOW_DESTRUCTIVE=1)

Examples:
  scp_api.py list   vpc /v1/vpcs rpv                 # do we have leftover terraform VPCs?
  scp_api.py exists vpc /v1/vpcs/<id>                # did terraform really create/destroy it?
  scp_api.py get    vpc /v1/transit-gateways/<id>    # inspect fields (required/optional values)
  scp_api.py delete vpc /v1/transit-gateways/<tgw>/vpc-connections/<conn>

Common paths (from the api_catalog): vpc host → /v1/vpcs/{id}, /v1/subnets/{id},
/v1/internet-gateways/{id}, /v1/publicips/{id}, /v1/ports/{id},
/v1/transit-gateways/{id}, /v1/transit-gateways/{tgw}/vpc-connections/{conn};
dns host → /v1/private-dns/{id}, /v1/public-domain-names/{id}.
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import sys
import time
import urllib.error
import urllib.request

GLOBAL_SERVICES = {
    "billingplan", "budget", "cloudcontrol", "costexplorer", "iam",
    "organization", "pricing", "product", "quota", "resourcemanager", "support",
}
# JS encodeURI() keeps these reserved/unreserved chars unescaped.
_ENCODE_SAFE = "!#$&'()*+,/:;=?@~"


def host(service: str) -> str:
    region = os.environ.get("SCP_REGION", "kr-west1")
    env = os.environ.get("SCP_ENV", "e")
    if service in GLOBAL_SERVICES:
        return f"https://{service}.{env}.samsungsdscloud.com"
    return f"https://{service}.{region}.{env}.samsungsdscloud.com"


def _headers(method: str, url: str) -> dict:
    ak = os.environ["SCP_ACCESS_KEY"]
    sk = os.environ["SCP_SECRET_KEY"]
    client_type = os.environ.get("SCP_CLIENT_TYPE", "Openapi")
    ts = str(int(time.time() * 1000))
    signed_url = urllib.parse.quote(url, safe=_ENCODE_SAFE)
    msg = (method.upper() + signed_url + ts + ak + client_type).encode("utf-8")
    sig = base64.b64encode(hmac.new(sk.encode("utf-8"), msg, hashlib.sha256).digest()).decode("ascii")
    return {
        "Scp-Accesskey": ak,
        "Scp-Signature": sig,
        "Scp-Timestamp": ts,
        "Scp-ClientType": client_type,
        "Accept-Language": "en-US",
        "Accept": "application/json",
        "Content-Type": "application/json",
    }


import urllib.parse  # noqa: E402  (after _ENCODE_SAFE def for clarity)


def call(method: str, service: str, path: str, body: dict | None = None):
    url = host(service) + path
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(url, data=data, method=method.upper(), headers=_headers(method, url))
    try:
        with urllib.request.urlopen(req, timeout=int(os.environ.get("SCP_TIMEOUT", "60"))) as r:
            return r.status, r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")
    except Exception as e:  # network/DNS
        return 0, f"ERROR: {e}"


def _items(body_text: str):
    try:
        b = json.loads(body_text)
    except Exception:
        return []
    if isinstance(b, list):
        return b
    if isinstance(b, dict):
        for v in b.values():
            if isinstance(v, list) and (not v or isinstance(v[0], dict)):
                return v
    return []


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__)
        return 2
    cmd, service, path = argv[0], argv[1], argv[2]
    if cmd == "get":
        st, body = call("GET", service, path)
        print(f"{st}\n{body}")
        return 0 if 200 <= st < 300 else 1
    if cmd == "exists":
        st, _ = call("GET", service, path)
        print("EXISTS" if 200 <= st < 300 else ("ABSENT" if st == 404 else f"STATUS {st}"))
        return 0
    if cmd == "list":
        prefix = argv[3] if len(argv) > 3 else ""
        st, body = call("GET", service, path)
        if not (200 <= st < 300):
            print(f"list {service}{path} -> {st}\n{body}")
            return 1
        for it in _items(body):
            name = (it.get("name") or it.get("volume_name") or "") if isinstance(it, dict) else ""
            if name.startswith(prefix):
                print(f"{it.get('id', it.get('volume_id', '?'))}\t{name}\t{it.get('state', '')}")
        return 0
    if cmd == "delete":
        if os.environ.get("SCP_ALLOW_DESTRUCTIVE", "").lower() not in ("1", "true", "yes"):
            print("refusing DELETE: set SCP_ALLOW_DESTRUCTIVE=1")
            return 2
        st, body = call("DELETE", service, path)
        print(f"DELETE {service}{path} -> {st}  {body[:200]}")
        return 0 if st in (200, 202, 204, 404) else 1
    print(f"unknown command: {cmd}\n{__doc__}")
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
