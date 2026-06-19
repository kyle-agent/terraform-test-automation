# DBaaS: cachestore / searchengine / sqlserver (+ eventstreams reference)

Companion prose for `coverage/domain.yaml › services.dbaas`. Extends the shared DBaaS
section in [`scp-domain-knowledge.md` §5](scp-domain-knowledge.md) (CREATING-trap,
name≤9, size_gb=104, service_ip auto-assign). Schema source: `api_docs.json`
`database/*` + `data-analytics/*`. Empirical values: `cmd/dbaas_probe/FINDINGS.md`.

> Confidence: schemas = confirmed (Open API ref); per-engine create results = confirmed
> (probe 202/400 runs); FAILED-state outcomes = confirmed (run 27406093988).

## 0. Common cluster create shape (`POST /v1/clusters`, one host per engine)
All four share this envelope — required fields: `name`, `instance_name_prefix`,
`subnet_id`, `timezone`, `dbaas_engine_version_id`, `init_config_option`,
`instance_groups`. Optional: `allowable_ip_addresses`, `nat_enabled`,
`maintenance_option`, `tags`.

Each `instance_groups[]` element: `role_type` (enum, per engine), `server_type_name`
(**must come from the live `/v1/server-types` catalog** — there is no provider data
source for it), `block_storage_groups[]` (OS group `size_gb` must be **104**;
`volume_type` ∈ `SSD, SSD_KMS, HDD, HDD_KMS`), `instances[]`.

Doc says cluster `name` is `^[a-zA-Z]*$` len 3–20, prefix `^[a-z][a-zA-Z0-9\-]*$` len
3–13 — **but the platform empirically caps name≤9, prefix≤8** (probe; the provider drops
the body so this shows as a bare `value_error`, #83). Use the empirical limits.

## 1. cachestore (Redis) — `RedisClusterCreateRequest`  ✅ CREATABLE
- Create proven **202** with valid catalog values (probe). Engine version from the
  `samsungcloudplatformv2_cachestore_engine_version` data source.
- `instance_groups[].role_type` enum: `MASTER, MASTER_REPLICA, REPLICA, SENTINEL`.
- `init_config_option` (`RedisInitConfigOption`): `database_user_password` **REQ**
  (8–…); `database_port` (default 6378), `sentinel_port` (26378), `backup_option` opt.
- Extra top-level: `ha_enabled`, `replica_count` (0–2), `timezone` REQ.
- **server_type_name gotcha (registry, runs 27661036920 / 27666147128):** both
  `redis1v1m2` and `redis1v2m4` returned 400 `"invalid data (Server type)"`. The valid
  `server_type_name` must be looked up live from the **cachestore** server-type/product
  catalog (`/v1/server-types`) with creds — guessed names fail. This is the one fix the
  fixture still needs.

## 2. searchengine (OpenSearch) — `SearchEngineClusterCreateRequest`  ⚠ creates → FAILED
- Required incl. `license` handling. `init_config_option`
  (`SearchEngineInitConfigOptionRequest`): `database_user_name` (`^[a-z]*$`),
  `database_user_password` REQ; `database_port` default 9200.
- Top-level `license` is **optional, `string|null`**, and `is_combined` toggles
  Master/Data server separation.
- **License crack (probe `searchengine-license`):** the fixture omitting `license`
  produced apply 400 `"Invalid License."` The probe iterates license variants in order
  *omitted → "" → null → OPEN_SOURCE → BASIC → ENTERPRISE*, stops at first 202. The doc
  example shows `license: ""`; the provider SDK field is `NullableString + omitempty` so
  "omitted" and `""` differ on the wire — that mismatch is the bug surface.
- **Outcome (run 27406093988):** even when create is **ACCEPTED (202)** with the
  OpenSearch image + license omitted, the cluster **provisions to `state: FAILED`** —
  platform-side, and the FAILED cluster **pins the pool subnet/VPC** until reaped.
  So this is blocked on a platform provisioning failure, not the request schema.

## 3. sqlserver — `SqlserverClusterCreateRequest`  ⚠ creates → FAILED
- Top-level adds `vip_public_ip_id`, `virtual_ip_address` (opt), `ha_enabled`.
- `init_config_option` (`SqlserverInitConfigOptionRequest`) is the richest:
  `license` **REQ**, `database_service_name` REQ (`^[A-Z][a-zA-Z]*$`),
  `database_user_name` REQ (`^[a-zA-Z0-9]*$`), `database_user_password` REQ,
  `databases[]` REQ, `database_collation` enum
  `(SQL_Latin1_General_CP1_CI_AS, Korean_Wansung_CS_AS, Chinese_PRC_CI_AS)`,
  `database_port` (1200–65535, default 2866), `audit_enabled` opt.
- **Engine version crack (probe `sqlserver-versions`):** fixture apply 400
  `"Invalid Engine Version."` The fixture picks the first non-`end_of_service`
  `/v1/engine-versions` entry (license `""`), and **that pick is not creatable**. The
  probe logs every engine-version row verbatim and tries the create per id until one
  202s. Not every listed version id is provisionable.
- **Outcome (run 27406093988):** with a base non-KB engine version the create is
  **ACCEPTED (202, probe 27403108280)** but the cluster **provisions to `state: FAILED`**
  on the pool subnet — platform-side; teardown left the subnet/VPC pinned (reaped).

## 4. eventstreams (Kafka) — `EventStreamsClusterCreateRequestV1Dot1`  (reference)
Kept for cross-reference — the canonical "opaque value_error" crack case.
- Required adds `service_watch_log_collection` (bool|null). Top-level `akhq_enabled`,
  `is_combined`.
- `init_config_option` (`EventStreamsInitConfigOptionRequest`): `broker_sasl_id`
  (`^[a-z]+$`, 2–…) + `broker_sasl_password` REQ, `zookeeper_sasl_id` +
  `zookeeper_sasl_password` REQ; `broker_port` (default 9091), `zookeeper_port`
  (2180), `akhq_id`/`akhq_password` opt.
- `instance_groups[].role_type` enum is huge (incl. `ZOOKEEPER_BROKER, BROKER,
  ZOOKEEPER, MASTER_DATA, DATA, KIBANA, DASHBOARDS, AKHQ, CONSOLE, …`).
- **Crack status (probe):** still 1 bare `value_error` after applying ZOOKEEPER_BROKER
  role + timezone. **NOT license, NOT role.** Hypothesis: cluster **topology** — the body
  has `is_combined:false` with a single instance group, so it likely needs **separate
  ZOOKEEPER + BROKER groups** (or `is_combined:true`) and/or the SASL fields. Needs the
  console-built example to resolve.

## 5. Highest-value facts for lifecycle agents
1. **server_type_name and dbaas_engine_version_id must be resolved live** from
   `/v1/server-types` and `/v1/engine-versions` — guessed names 400. Not every listed
   engine-version id is provisionable (sqlserver).
2. **searchengine + sqlserver: create is ACCEPTED but the cluster goes `state: FAILED`**
   (platform-side). Treat as platform-blocked, not a fixture/schema bug; a FAILED
   cluster **pins its subnet/VPC** → must be reaped.
3. **cachestore is creatable (202)** once `server_type_name` comes from the live
   catalog — it is the closest-to-green of the three.
4. **license wire-format mismatch** (searchengine): omitted vs `""` vs `null` differ
   because of SDK `NullableString + omitempty`; doc example is `license: ""`.
5. The provider **drops the API error body (#83)** → every constraint above surfaces as
   a bare `value_error`; use `cmd/dbaas_probe/probe.py` to see the real message.
