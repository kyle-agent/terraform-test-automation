---
name: scp-api
description: Auxiliary Samsung Cloud Platform (SCP) Open API helper for the terraform test workflow. Use it ONLY as a supplement to terraform — never as the primary test path. Reach for it when (1) terraform cannot delete a resource because the provider implements no ImportState (issue #81) and a leaked/orphaned resource must be removed by id; (2) you need to confirm whether a terraform-created resource actually exists in the account (e.g. verify a create/destroy really happened, or hunt leaks); or (3) you need to look up a resource's real required/optional field values from the live API or the endpoint catalog. Keywords: SCP REST API, delete leaked VPC/transit gateway/DNS by id, cleanup orphaned resources, check resource exists, HMAC auth, Scp-Accesskey/Scp-Signature.
---

# SCP Open API helper (auxiliary to terraform testing)

**Main goal stays terraform**: create → modify → destroy fixtures, capture provider
issues, repeat. This skill is the *secondary* tool for the gaps terraform leaves.

## When to use
- **Cleanup terraform can't do.** The provider implements **no `ImportState` on any
  resource (#81)**, so `terraform import` + destroy can't adopt/remove orphans. When a
  lifecycle leaks a resource (e.g. an apply failed, a destroy 409'd, a run was
  cancelled), delete it **by id** via the API.
- **Existence / leak checks.** `list`/`exists` to confirm a terraform create or destroy
  really took effect, or to sweep for leftovers (names like `rpv*`, `regr*`).
- **Field lookup.** `get` an existing resource (or read the catalog) to learn the real
  required/optional attributes when a fixture fails with "X is required".

## Auth (HMAC — proven, no token/SDK needed)
`signing_string = METHOD + encodeURI(full_url) + timestamp_ms + accessKey + clientType`,
`signature = Base64(HMAC_SHA256(secretKey, signing_string))`, sent as headers
`Scp-Accesskey`, `Scp-Signature`, `Scp-Timestamp`, `Scp-ClientType=Openapi`,
`Accept-Language`. Per-service hosts: regional
`https://<service>.<region>.<env>.samsungsdscloud.com` (vpc, dns, virtualserver, ske,
mysql, …); global `https://<service>.<env>.samsungsdscloud.com` (iam, product, billing,
resourcemanager, …). This is the scheme used by the canonical
`kyle-agent/api-test-automation` framework (its `framework/api_catalog.json` is the full
endpoint reference).

## How to run
Self-contained CLI: `scp_api.py` (stdlib only). Env required: `SCP_ACCESS_KEY`,
`SCP_SECRET_KEY`, `SCP_REGION` (e.g. `kr-west1`), `SCP_ENV` (e.g. `e`). Destructive
calls also need `SCP_ALLOW_DESTRUCTIVE=1`.

```bash
# locally only works with creds in env; in CI run inside the scp-integration environment
export SCP_ACCESS_KEY=$SCP_TF_ACCESS_KEY SCP_SECRET_KEY=$SCP_TF_SECRET_KEY
export SCP_REGION=kr-west1 SCP_ENV=e
python .claude/skills/scp-api/scp_api.py list   vpc /v1/vpcs rpv          # leftover tf VPCs?
python .claude/skills/scp-api/scp_api.py exists vpc /v1/vpcs/<id>          # create/destroy real?
python .claude/skills/scp-api/scp_api.py get    dns /v1/private-dns/<id>   # inspect fields
SCP_ALLOW_DESTRUCTIVE=1 \
python .claude/skills/scp-api/scp_api.py delete vpc /v1/vpcs/<id>          # remove an orphan
```

**In CI** (the account creds are GitHub secrets, not local): use the
`.github/workflows/api-reaper.yml` job (runs in `environment: scp-integration`, maps
`SCP_TF_ACCESS_KEY/SECRET_KEY` → `SCP_ACCESS_KEY/SECRET_KEY`). Edit the target list in
`cmd/api_reaper/reap.py` for one-off cleanups, or call `scp_api.py` from a step.

## Confirming DBaaS create values (issue #83)
DBaaS clusters `plan` fine but `apply` fails with an opaque `400 value_error` that
names no field (the provider drops the response body). Two ground truths make this
tractable:
- **`framework/api_bodies.json`** in `kyle-agent/api-test-automation` holds the
  *proven-valid* create body for every engine (`database/<engine>/<engine>createcluster`,
  `data-analytics/{eventstreams,searchengine}/...`). It is the value reference:
  e.g. mysql wants `database_port: 2866`, `database_character_set: "utf8mb4"`,
  `block_storage_groups` OS `size_gb: 104`, an instance `service_ip_address`
  (`192.168.10.10/32`), `maintenance_option {period_hour,starting_day_of_week,
  starting_time}`, `timezone: "Asia/Seoul"`, and a real `server_type_name`.
- **`cmd/dbaas_probe/probe.py`** POSTs that body straight to `<engine>/v1/clusters`
  (looking up live `dbaas_engine_version_id` from `/v1/engine-versions`,
  `server_type_name` from `/v1/server-types`, and a `subnet_id`) and prints the RAW
  status+body — so the offending field is visible. Created clusters are DELETEd
  (leak 0). Run it via `.github/workflows/dbaas-probe.yml` (CI has the creds):
  dispatch with `engines = "mysql"` / `"all"`, or push to trigger. If the raw API
  *accepts* a body the provider rejects, that isolates a provider-mapping bug.

## Cleanup dependency order (important)
A VPC won't delete until its children are gone. Delete in order:
`ske clusters (nodepools→cluster) → ports → subnets → internet-gateways → publicips →
transit gateways → (private-dns / public-domain detached) → vpc`.

**Transit Gateway has its OWN required teardown order** (a TGW won't delete while rules
or connections remain): **routing-rules + uplink-routing-rules → firewalls →
vpc-connections → the TGW**. (Confirmed live — deleting only the vpc-connection is not
enough; leftover routing rules block it.)

Public Domain Name has **no DELETE API** (only create/list/get/set/transfer) — it can't
be reaped via API; release/console only. The reaper waits for async (202) deletes and
retries VPC 409s. **Only ever target specific ids / vpc_id-scoped children on a shared
account** — never broad name-prefix deletes that could hit live resources.

## Common DELETE paths (from api_catalog.json)
- vpc host: `/v1/vpcs/{id}`, `/v1/subnets/{id}`, `/v1/internet-gateways/{id}`,
  `/v1/publicips/{id}`, `/v1/ports/{id}`, `/v1/transit-gateways/{id}`,
  `/v1/transit-gateways/{tgw}/vpc-connections/{conn}`
- dns host: `/v1/private-dns/{id}`, `/v1/public-domain-names/{id}`

## Known provider gaps that make this skill necessary
#81 no ImportState (can't tf-clean leaks) · #76 VPC/TGW status-waiter hang · #77 LB
create no-wait → destroy leak · #79 private-dns destroy 409 · #82 create returns 500 but
leaves the resource (public-domain-name) → orphan.
