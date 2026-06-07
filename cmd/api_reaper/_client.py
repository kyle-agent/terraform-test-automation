#!/usr/bin/env python3
"""Self-contained SCP Open API client for the reaper (stdlib only).

Replaces the dependency on cloning kyle-agent/api-test-automation (whose
`framework` module import broke the reaper when that repo changed). Mirrors the
proven HMAC scheme used by .claude/skills/scp-api/scp_api.py, and exposes the
small interface the reaper scripts use:

    from _client import settings, ApiClient, MutationBlocked
    c = ApiClient(settings); r = c.get("/v1/vpcs", service="vpc")
    r.status, r.ok, r.body   # body is parsed JSON (dict/list) or {}

Env: SCP_ACCESS_KEY, SCP_SECRET_KEY, SCP_REGION (e.g. kr-west1), SCP_ENV (e.g. e).
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import json as _json
import os
import time
import urllib.error
import urllib.parse
import urllib.request

GLOBAL_SERVICES = {
    "billingplan", "budget", "cloudcontrol", "costexplorer", "iam",
    "organization", "pricing", "product", "quota", "resourcemanager", "support",
}
_ENCODE_SAFE = "!#$&'()*+,/:;=?@~"


class MutationBlocked(Exception):
    pass


class _Settings:
    @property
    def region(self):
        return os.environ.get("SCP_REGION", "kr-west1")

    @property
    def env_code(self):
        return os.environ.get("SCP_ENV", "e")

    def require_credentials(self):
        if not os.environ.get("SCP_ACCESS_KEY") or not os.environ.get("SCP_SECRET_KEY"):
            raise SystemExit("SCP_ACCESS_KEY / SCP_SECRET_KEY required")


settings = _Settings()


class Resp:
    def __init__(self, status, text):
        self.status = status
        self.text = text
        try:
            self.body = _json.loads(text) if text else {}
        except ValueError:
            self.body = {}

    @property
    def ok(self):
        return 200 <= self.status < 300


def _host(service):
    region = settings.region
    env = settings.env_code
    if service in GLOBAL_SERVICES:
        return f"https://{service}.{env}.samsungsdscloud.com"
    return f"https://{service}.{region}.{env}.samsungsdscloud.com"


def _headers(method, url):
    ak = os.environ["SCP_ACCESS_KEY"]
    sk = os.environ["SCP_SECRET_KEY"]
    ct = os.environ.get("SCP_CLIENT_TYPE", "Openapi")
    ts = str(int(time.time() * 1000))
    signed = urllib.parse.quote(url, safe=_ENCODE_SAFE)
    msg = (method.upper() + signed + ts + ak + ct).encode()
    sig = base64.b64encode(hmac.new(sk.encode(), msg, hashlib.sha256).digest()).decode()
    return {
        "Scp-Accesskey": ak, "Scp-Signature": sig, "Scp-Timestamp": ts,
        "Scp-ClientType": ct, "Accept-Language": "en-US",
        "Accept": "application/json", "Content-Type": "application/json",
    }


class ApiClient:
    def __init__(self, _settings=None):
        pass

    def _do(self, method, path, service, json=None):
        url = _host(service) + path
        data = _json.dumps(json).encode() if json is not None else None
        req = urllib.request.Request(url, data=data, method=method.upper(),
                                     headers=_headers(method, url))
        try:
            with urllib.request.urlopen(req, timeout=int(os.environ.get("SCP_TIMEOUT", "60"))) as r:
                return Resp(r.status, r.read().decode("utf-8", "replace"))
        except urllib.error.HTTPError as e:
            return Resp(e.code, e.read().decode("utf-8", "replace"))

    def get(self, path, service=None, **kw):
        return self._do("GET", path, service)

    def delete(self, path, service=None, json=None, **kw):
        return self._do("DELETE", path, service, json=json)

    def post(self, path, service=None, json=None, **kw):
        return self._do("POST", path, service, json=json)
