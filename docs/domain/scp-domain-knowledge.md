# SCP domain knowledge (human-readable)

The prose companion to [`coverage/domain.yaml`](../../coverage/domain.yaml). Keep the
two in sync. This explains *why* each fact holds and where it came from, so humans can
trust and edit it. Scope: what an agent must know to create, test, and clean up SCP
resources correctly.

> Maintained by the Domain-Knowledge-Curator agent; **human-owned** (edit freely).
> Deeper empirical sources: [`cmd/dbaas_probe/FINDINGS.md`](../../cmd/dbaas_probe/FINDINGS.md),
> [`docs/findings/regression-idempotency.md`](findings/regression-idempotency.md),
> [`.claude/skills/scp-api/SKILL.md`](../../.claude/skills/scp-api/SKILL.md),
> [`docs/TEST_STRATEGY.md`](../TEST_STRATEGY.md).

## 1. Account & platform facts
- Dedicated single-tenant test account `9b13e0d04b7544ad8b66905cd94888bd`,
  region `kr-west1`, env `e`. Provider mirror pinned at **v3.3.2**.
- **VPC quota = 5.** This is the central bottleneck for the whole test architecture: a
  single leaked VPC starves the pool lane. Leak-0 is mandatory; the API reaper is the
  safety net.
- SCP Open API host scheme: regional `https://<service>.<region>.<env>.samsungsdscloud.com`,
  global services drop the region (iam, billing, resourcemanager, quota, …). HMAC auth.

## 2. Resource dependency graph (the core "domain rule")
**To create a resource you must first create its prerequisites.** Destroy in reverse.

```
vpc
 └─ subnet
     ├─ security_group ──┐
     ├─ internet_gateway → (auto-creates a firewall; exposes firewall_id)
     ├─ port / nat_gateway
     ├─ virtual_server  (also needs: keypair, image, server_type)
     │     └─ block_storage volume (attaches to a server)
     ├─ load_balancer
     │     └─ lb_server_group → lb_listener / lb_member ; lb_health_check
     ├─ dbaas_cluster  (mysql/postgresql/mariadb/sqlserver/epas/cachestore/vertica/
     │                   searchengine/eventstreams)
     └─ ske_cluster
```
Canonical example: **a virtual server requires a VPC + subnet (+ security group,
keypair, image, server type) first.** This is exactly the kind of rule each service
agent reads from `domain.yaml` before acting.

The test harness encodes this two ways: the **pool bootstrap** pre-creates the shared
VPC + prereqs (`bootstrap/`), and **self-contained** scenarios create their own VPC.

## 3. Cleanup ordering (children before parents)
A VPC will not delete until every child is gone. The reaper deletes in this order:
`ske/dbaas/servers → loadbalancer children → loadbalancer → ports → nat-gateways →
publicips → vpc-peerings → vpc-endpoints → private-nats → subnet-vips → subnets →
internet-gateways → vpc`.
- **Transit Gateway** has its own order: `routing-rules + uplink-rules → firewalls →
  vpc-connections → TGW` (rules/connections block the delete).
- **public-domain-name** has **no delete API** → console/release only.
- **Block storage volumes (VM)** live at the `virtualserver` host `/v1/volumes`
  (not `/v1/block-storages`, which 403s).

## 4. Async & state-trap behaviours
- **DBaaS CREATING-trap:** a freshly created cluster is **non-deletable for ~15–20 min**
  until it reaches ACTIVE; `DELETE` returns `400 Dbaas.ValidationError.InvalidServiceState`
  during that window, then `202`. The provider's create waits for ACTIVE (so the
  terraform path is clean); API-direct creates must poll ACTIVE before delete. The
  reaper retries transitional `400/409/500` with backoff.
- Many deletes are **async** (`202` + poll / `wait_gone`).
- A still-terminating DBaaS cluster **pins its subnet** → subnet/VPC `409` until gone.

## 5. DBaaS create constraints (hidden by opaque errors — issue #83)
The provider drops the API error body, so failures show as `400 value_error` naming no
field. Probing the raw API (`cmd/dbaas_probe`) revealed:
- `name` ≤ 9 chars; `instance_name_prefix` ≤ 8 chars.
- `init_config_option.database_name / database_user_name / database_user_password`
  must be **non-empty** (never null).
- OS `block_storage_groups.size_gb` must be **104** (fixed).
- `service_ip_address` must be a **free IP in the subnet**, or **omit** to auto-assign
  (never null).
- mysql/postgresql/mariadb/epas/cachestore create cleanly with these; sqlserver /
  searchengine / eventstreams still have one unnamed `value_error` each (see
  `cmd/dbaas_probe/FINDINGS.md`).

## 6. ServiceWatch log groups (cleanup gotcha)
- The log-group list **paginates** (`?size=100&page=N`; default ~20) and is
  **principal-scoped**: our key only lists/deletes groups it owns.
- Delete is **bulk**: `DELETE /v1/log-groups {"ids":[...]}`.
- DBaaS (slowlog/alertlog), SKE, and **SCF** auto-create log groups under the
  *service* principal → our key gets `403`; they only clear when the **parent**
  resource is deleted. (This explains "console shows ~400 but our key sees ~6".)

## 7. Permission boundaries (BLOCKED, not bugs)
Our test/reaper key gets `403`/`401` on: `scf`, `backup`, `gslb`, `baremetal`,
`multinodegpucluster`, `iam_user` (401 HMAC), `loggingaudit`. Resources there can't be
created/cleaned with the current key — classify as BLOCKED, not provider defects.

## 8. Known provider issues
Cross-referenced in `coverage/domain.yaml` and detailed in
[`docs/PROVIDER_ISSUES.md`](../PROVIDER_ISSUES.md).
