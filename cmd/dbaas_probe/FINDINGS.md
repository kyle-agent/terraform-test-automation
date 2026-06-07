# DBaaS create — value findings (via cmd/dbaas_probe/probe.py)

Method: POST the proven-valid `api_bodies.json` create body straight to the Open
API and read the raw response (the provider drops the body — issue #83). Looked up
live `dbaas_engine_version_id` (`/v1/engine-versions`), `server_type_name`
(`/v1/server-types`) and a subnet; `name`/`instance_name_prefix` short & letters-only.

## Key result

With **`service_ip_address` omitted/blank, the API auto-assigns a free IP** and the
create succeeds (HTTP 202). Confirmed live:

| engine | result | remaining gap |
|---|---|---|
| mysql | **202 CREATED** (blank service_ip) | none — values valid |
| postgresql | **202 CREATED** | none |
| mariadb | **202 CREATED** | none |
| epas | **202 CREATED** | none |
| cachestore | **202 CREATED** | none |
| sqlserver | 400 `["value_error"]` (was 2) | fill set role_type/databases[].database_name; **1 unnamed value_error remains** — likely `license` and/or `database_service_name` |
| searchengine | 400 `["value_error"]` (was 2) | fill set timezone/backup; **1 unnamed value_error remains** |
| eventstreams | 400 `["value_error"]` | **NOT license, NOT role** — ZOOKEEPER_BROKER role + timezone both applied, still 1 unnamed value_error. Likely the cluster **topology**: body has `is_combined:false` with a single instance group, so it probably needs separate ZOOKEEPER + BROKER groups (or `is_combined:true`) and/or SASL fields. Needs the API schema/console. |

The 3 remaining engines each hit a single **bare `value_error` with no field name** — the API itself is opaque here (see #83), so resolving them needs the documented request schema or a console-built example, not more guess-and-check.

So our terraform fixtures for **mysql/postgresql/mariadb/epas/cachestore are correct**
(they omit `service_ip_address`, use `size_gb=104`, resolve `dbaas_engine_version_id`
from the `*_engine_version` data source, name `^[a-zA-Z]*`); they should apply green
on a fresh bootstrap subnet (the pool sweep's vpc3 shard).

## Constraints surfaced (each hidden by terraform's bare `value_error`)

1. `name` / `instance_name_prefix` have a small `max_length` (canonical name<=9,
   prefix<=8); 15 chars → `"...string longer than the max_length constraint..."`.
2. `init_config_option.database_name` / `database_user_name` / `database_user_password`
   must be non-empty.
3. OS `block_storage_groups` `size_gb` must be **104**.
4. `service_ip_address`, if set, must be a **free** IP in the subnet
   (`"<ip> is not available"`); low IPs are reserved. **Omit it to auto-assign.**

## CREATING-trap (relevant to provider issues #76/#77)

A freshly created DBaaS cluster sits in a non-deletable state (`DELETE` → 400) for
**~15-20 min** until it goes active; only then does `DELETE` return 202. So a create
that isn't waited on cannot be torn down promptly — `delete_cluster()` in probe.py
polls and retries to handle this, and `probe.py cleanup` removes leaked ids.

## How to run

`.github/workflows/dbaas-probe.yml` (env `scp-integration`). Default action is
`cleanup` (safe/idempotent). Flip the run arg to `mysql` / `all` /
`"sqlserver searchengine eventstreams"` for one push to probe, then flip back.
Created clusters self-delete (202 id is under `resource.id`).
