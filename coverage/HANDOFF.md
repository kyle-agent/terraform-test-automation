# Coverage-expansion session handoff

**Branch:** `claude/youthful-albattani-CzhCZ` (both repos)
**Last updated:** 2026-06-07
**Purpose:** Single source of truth for resuming the Terraform-provider coverage
expansion work in a fresh session. Read this file first, then `coverage/registry.yaml`.

---

## 1. What this project does

`terraform-test-automation` exercises every resource in the
`samsungcloudplatformv2` Terraform provider against a **dedicated single-tenant
SCP test account** (account `9b13e0d04b7544ad8b66905cd94888bd`, region
`kr-west1`, env `e`) and records a per-stage capability matrix
(validate / plan / apply / replan / update / import / destroy / destroy_verify).

- **Source of truth:** `coverage/registry.yaml` — one entry per scenario with
  `status` (green / broken / untested / excluded), `vpc` lane (none / pool / self),
  `needs`, `depends_on`, `issues`, `cost`, etc. Validated by
  `scripts/validate_registry.py`. (Originally seeded by `scripts/gen_registry.py`;
  now hand-edited. Re-dump style: `yaml.safe_dump(sort_keys=True,
  default_flow_style=False, width=100)` — keep diffs minimal.)
- **Scenarios:** `scenarios/<name>/main.tf` — each a self-contained fixture with
  offline-safe defaults so `terraform validate` passes without creds.
- **Matrix runner:** `tests/capability` (Go), driven by env
  `MATRIX_SCENARIOS`, `DESTROY_VERIFY=1`, `CAPABILITY_MATRIX=1`.

### Lanes (set by `scripts/plan_matrix.py`)
- `none` (novpc): no VPC needed; run in parallel.
- `pool`: share one bootstrapped VPC + prereqs (subnet, SG, public IP, keypair,
  IGW+firewall, filestorage, image lookup). Bootstrapped in `bootstrap/`, torn
  down `if: always()` at job end. TF_VARs (vpc_id, subnet_id, security_group_id,
  publicip_id, ip_address, keypair_name, image_id, server_type_id, volume_id,
  kubernetes_version, …) are injected from bootstrap outputs.
- `self` (selfvpc): scenario creates its own VPC; runs **after** pool, low parallel.

### How to run a sweep
- **Push trigger** (re-added this session): pushing to `claude/**` touching
  `.github/workflows/coverage-sweep-pool.yml`, `coverage/registry.yaml`, or
  `scripts/plan_matrix.py` runs `coverage-sweep-pool.yml` with
  `SELECT_STATUS='untested'` (discovery of newly-flipped scenarios).
- **Manual:** `workflow_dispatch` on *Coverage Sweep Pool* (inputs:
  `select_status`, `select_vpc`, `select_family`). NOTE: API `workflow_dispatch`
  is **403 for the integration token** — use the Actions UI, or the push trigger.
- **No cron** anywhere (deliberate — nothing runs automatically on the paid
  dedicated account).

### Leak cleanup — the API reaper
- `cmd/api_reaper/sweep_all.py` deletes test-created resources **by id via the
  Open API** (HMAC), in dependency order (children→parents), covering
  loadbalancers, subnets, VPCs, TGWs, etc. Needed because the provider implements
  no ImportState for many resources (issue #81), so terraform alone can't always
  clean leaks.
- Trigger: **push to `claude/**` touching `cmd/api_reaper/{sweep_all,reap,_client}.py`
  or `.github/workflows/api-reaper.yml`** (this path is NOT in coverage-sweep's
  paths, so a reaper-only commit won't re-trigger a coverage run). On push/manual:
  `SWEEP_MIN_AGE_HOURS=0`, `SWEEP_ALL=1` (deletes everything on the account, guarded
  by `EXPECTED_ACCOUNT_ID`). Also sweeps leaked OBS buckets via `scripts/obs_bucket.py`.
- **VPC quota is 5.** Leaked VPCs are the main recurring hazard — always confirm
  pool teardown succeeded, and reap if a subnet/VPC delete 409s.

---

## 2. This session's goal & track selection

User chose 3 tracks to pursue (DBaaS #83 explicitly de-scoped — needs the user's
own console payloads):

1. **Tier-1 free re-runs + fixture fixes** — retest scenarios that were only
   "broken" due to prior account leaks/quota, and fix self-containable fixtures.
2. **Load balancer ×7 reconsideration** — un-exclude the 7 `loadbalancer_*`
   scenarios now that the reaper tears down LB children (was excluded for #77
   destroy-leak).
3. **`virtualserver_image` via OBS** — upload a real image file to OBS and point
   the fixture's `image_url` at it.

---

## 3. Work done this session

### Registry flips (commit 137282e)
- `vpn_vpn_gateway`, `vpn_vpn_tunnel`: broken → **untested** (retest; the "broken"
  was quota-masking from peering leaks, not a real failure).
- `servicewatch_log_stream`: broken → **untested** (already self-contained — it
  creates its own parent log group).
- `loadbalancer_basic`: excluded → **untested** (premise test for track 2).
- Cleared stale `issues` on those four.

### Workflow trigger restored (commit 137282e)
- Re-added the `push` trigger to `coverage-sweep-pool.yml` (claude/**, scoped to
  the 3 paths above) so coverage runs are drivable from a push.

### Reaper triggered (commit 38921bf)
- Touched `api-reaper.yml` to fire a sweep and reclaim a leaked pool VPC (see §4).

### Reaper gap fixed — ServiceWatch log groups (commit 845ca07)
- The reaper covered **no** ServiceWatch resources, so log groups (and nested log
  streams) accumulated every run. Added `reap_servicewatch()` to `sweep_all.py`:
  self-discovers the collection path (`/v1/log-groups` on host
  `servicewatch.kr-west1.e.samsungsdscloud.com`), **bulk-deletes** via
  `DELETE /v1/log-groups {"ids":[...]}`, with id-field + per-id/stream-clear
  fallbacks. Now part of every sweep.
- Confirmed by reaper run `27115120403`: found **20** log groups
  (ske/mysql/mariadb/scf `slowlog`·`alertlog` auto-created groups) and deleted all
  in one bulk call (`DELETE … -> 200`, `sweep_all done: 32 deleted`).
- NOTE: many of these are **auto-created by other services** (DBaaS/SKE/SCF), not
  just the servicewatch fixtures — they reappear whenever those resources run, so
  the recurring reaper sweep (not a one-off) is what keeps them clear.

---

## 4. Batch-1 run results — run `27095226766` (commit 137282e)

All 4 jobs green at orchestration level. Per-scenario verdicts:

| scenario | lane | verdict |
|---|---|---|
| `vpn_vpn_gateway` | self | ✅ **GREEN** — validate→apply→replan→destroy→destroy_verify all ✅ |
| `vpn_vpn_tunnel` | self | ✅ **GREEN** — all stages ✅ |
| `servicewatch_log_stream` | none | ✅ green (log_group + log_stream apply/replan/destroy ✅) |
| `loadbalancer_basic` | pool | ❌ applied, but **leaked the LB on destroy (#77)** → pool subnet/VPC teardown 409'd (CONFIRMED leaker) |
| `vpc_private_nat_ip` | pool | ✅ not the leaker (reaper found no leaked private-nat); treat as passing — re-confirm its matrix |

**The pool bootstrap teardown failed:**
```
Error: Error Deleting subnet
Could not delete subnet, unexpected error: 409 Conflict
Reason: Cannot terminate due to associated resources.
```
The bootstrap destroyed 6/7 prereqs; the **subnet delete 409'd because a scenario
left a resource attached**, so the **VPC delete never ran → pool VPC leaked**
(quota hazard). Teardown uses `|| true`, so the job still reported success — do
not trust job-level "success"; always check the teardown step + matrix.

> **RESOLVED:** API Reaper run `27106727666` (commit 38921bf) finished `success`
> and its sweep log shows it deleted **2 loadbalancers** + the pool subnet
> `d2b58daf…` + the pool VPC `f32a21d9…` → **`loadbalancer_basic` is the leaker
> (#77 confirmed); the leaked pool VPC was reclaimed.** No leaked private-nat was
> found, so `vpc_private_nat_ip` did not leak.
>
> ⚠️ **Residual leftover for next session:** a few older VPCs still 409 on delete,
> each pinned by an ACTIVE `regrsub*` subnet that itself won't delete (run
> `27115120403` showed VPCs `1ffe9883…`/`c54babfe…` blocked by subnets
> `regrsub6a263eb9`/`regrsub6a260c25`; an earlier pass showed `257aca2c…` blocked
> by a subnet + an unnamed port `acbb5f5e…`). The reaper retries the subnet 6×
> then the VPC 6× and still 409s, so something the per-type sweep doesn't
> enumerate is pinning these subnets (ports? a VIP/static-nat? check the subnet's
> SHOW body). These are slowly accumulating — investigate what pins a stuck
> `regrsub*` subnet and extend the reaper, or delete by id via the scp-api skill.

### Conclusions
- **vpn gateway/tunnel were never really broken** — clean-account retest passes.
  → set both to **green**.
- **servicewatch_log_stream** passes self-contained → set **green**.
- **loadbalancer_basic** confirms #77: it applies/replans fine but **leaks on
  destroy**, blocking pool subnet/VPC teardown. The reaper *can* reclaim it, but
  the reaper runs out-of-band, so every LB run leaves a transient VPC leak until
  swept. **Decision needed** (see §5, track 2).

---

## 5. Remaining TODO (with concrete plans)

### Track 1 — fixture fixes still open
- **`firewall_firewall_rule`** (broken: "404 needs firewall target"). Plan:
  make **self-contained** — add `vpc_vpc` + `vpc_internet_gateway` (IGW
  auto-creates a firewall) and wire `firewall_id =
  samsungcloudplatformv2_vpc_internet_gateway.regr.firewall_id` (confirmed: the
  IGW resource exposes a computed `firewall_id`; e.g. bootstrap IGW showed
  `firewall_id = 2df9b387ca2445e8991caa52ad2c0970`). This converts it to a
  `vpc: self` scenario. IGW required args seen in bootstrap: `vpc_id`, `type="IGW"`,
  `firewall_enabled`, `firewall_loggable`.
- **`iam_role_policy_bindings`** (broken: "404 needs own role"). Plan: self-contain
  by creating an `iam_role` + `iam_policy` and binding them. **Risk:** `iam_role`
  itself is broken (#75) — if role *create* is broken this stays blocked. Verify
  `iam_role` apply independently first; if create works, self-contain.
- **`vpc_vpc_endpoint`** (broken: 400 "VPC Endpoint Type Subnet not found"). Needs
  config investigation — likely the `endpoint_ip_address` must sit inside the pool
  subnet CIDR (`192.168.0.0/27`, usable .1–.30; default fixture uses .30) and/or
  `resource_type`/`resource_key`/`resource_info` for OBS need correct values.
  Could be a provider/platform limitation — timebox it.

### Track 2 — load balancers (7 scenarios)
LB set: `loadbalancer_basic` (untested), and **excluded**:
`loadbalancer_lb_health_check`, `loadbalancer_lb_listener`, `loadbalancer_lb_member`,
`loadbalancer_lb_server_group`, `loadbalancer_loadbalancer_private_nat_ip`,
`loadbalancer_loadbalancer_public_nat_ip`.
- Premise confirmed: LB **applies/replans fine but destroy-leaks (#77)**, leaving
  the pool VPC unreclaimable by terraform → reaper must sweep.
- **Open decision:** is a transient per-run VPC leak (reclaimed only by an
  out-of-band reaper) acceptable to gain apply/replan coverage? Options:
  (a) keep LB scenarios **excluded** (status quo, no leak); (b) mark
  **broken #77** and run only in dedicated sweeps that always reap after; (c) add
  an **always-reap step** to the LB lane so the leak is cleaned in-run.
  **Recommend (c)** if pursuing LB coverage; otherwise leave excluded.
- The 6 sub-resource LB scenarios (listener/member/server_group/health_check/
  nat_ips) also need their inter-dependencies wired (listener/member need a
  server_group + LB id) before they can run.

### Track 3 — `virtualserver_image` via OBS
- Currently broken: "invalid OBS image URL (needs real image file)". Fixture
  (`scenarios/virtualserver_image/main.tf`) registers an image from
  `var.image_url` (disk_format=qcow2, container_format=bare, os_distro=ubuntu).
- Plan: upload a **real, valid** disk image to OBS (use `scripts/obs_bucket.py`
  patterns + boto3; OBS endpoint `https://object-store.kr-west1.e.samsungsdscloud.com`),
  make it readable, and pass its URL via `TF_VAR_image_url`. **Caveat:** a real
  Ubuntu cloud image is ~600 MB (heavy upload + platform import time/cost). A tiny
  valid qcow2 may be rejected by the platform's import validation — verify. Timebox;
  if the platform rejects small images, mark blocked with findings.

---

## 6. Registry state — DONE this session (now safe)

Already applied (commit with this doc). **`untested` count is now 0**, so a push
of `registry.yaml` triggers an *empty* coverage matrix (no bootstrap, no leak):
- `vpn_vpn_gateway` → **green** ✅
- `vpn_vpn_tunnel` → **green** ✅
- `servicewatch_log_stream` → **green** ✅
- `loadbalancer_basic` → **broken** (`#77` destroy-leak)
- `vpc_private_nat_ip` → **broken** (pending leaker confirmation — see §4; if the
  reaper log shows it did NOT leak and it passed cleanly, flip back to **green**)

**Pushing is safe.** When you flip a scenario to `untested` to test it, expect a
coverage run; always confirm pool teardown + reap after.

---

## 7. Key facts / gotchas
- Account `9b13e0d04b7544ad8b66905cd94888bd`, region `kr-west1`, env `e`.
- **VPC quota = 5**; leaked VPCs are the main hazard.
- Pool bootstrap: VPC `192.168.0.0/24`, subnet `192.168.0.0/27`, IGW w/ firewall.
- `server_type_id=s1v1m2`; image lookup picks newest Ubuntu (e.g. Ubuntu 24.04).
- Provider mirror pinned to `v3.3.2` in the workflows.
- IGW resource exposes computed `firewall_id` (useful for firewall_firewall_rule).
- Job-level "success" is unreliable (teardown is `|| true`); read the matrix +
  teardown step.
- Issue tags referenced: #58 (iam_access_key), #59/#60 (vpc_subnet/cidr), #69
  (virtualserver_volume), #75 (iam_role), #76 (vpc_private_nat/TGW), #77 (LB
  destroy-leak), #81 (no ImportState → reaper), #82 (dns 500), #83 (DBaaS family).

---

## 8. Account cleanup state & reaper findings (2026-06-08)

Triggered by leftovers piling up (ServiceWatch log groups, stuck subnets/VPCs).
Reaper (`cmd/api_reaper/sweep_all.py`) was extended; key findings:

- **No cron anywhere; nothing auto-runs.** All workflows (coverage-sweep-pool,
  dbaas-probe, obs-probe, inventory) are push(`claude/**`, path-scoped) or
  workflow_dispatch only. "Stop all tests" = already true when nothing is
  in-progress/queued. The producers of the leaked DBaaS resources are
  `dbaas-probe` (this repo, `cmd/dbaas_probe/probe.py`, creates+deletes clusters)
  and/or the external `api-test-automation` regression (out of our repo scope).
- **ServiceWatch reaper added + paginated** (commits 845ca07, 1f29952). Drains
  every log group OUR key owns. BUT: the list endpoint is **principal-scoped** —
  it returns only `count: N` groups created by our access key (`2a579fc…`). The
  ~400 groups seen in the **console are owned by managed-service principals**
  (e.g. SCF `bc371a79…`, DBaaS `1f0465d2…`): our key gets **403** on delete and
  can't even list them. **This is an IAM permission boundary, not a reaper bug.**
  To clear those: delete from the console as the account owner, OR grant the
  reaper's IAM key ServiceWatch delete perms, OR delete the owning parent
  resource (SCF function / DB cluster) so the service removes its own log groups.
- **DBaaS cluster delete `400` diagnosed** (commit c12e1e7): body =
  `Dbaas.ValidationError.InvalidServiceState` ("Invalid service state") — the
  cluster was mid-create/terminate. Fix: retry delete with backoff (now in the
  reaper); confirmed clusters then go 400→404 / →202 and release their pinned
  subnet/VPC (those were the stuck `regrsub* "API regression"` subnets). So the
  stuck-subnet mystery = a still-settling DBaaS cluster pinning the subnet.
- **Still unreapable by our key (need console/owner action):** 2 SCF log groups
  (`/scp/scf/regrscf6a25917a`, `…6a242ac1`, 403); ~5 stale `lb-health-checks`
  that 400; and the bulk of the console's ~400 log groups (foreign principals).
- **"failed resource" deletion:** the reaper deletes by id regardless of status,
  but the platform rejects deletes of resources in a bad/transitional state
  (DBaaS 400 InvalidServiceState, subnet/VPC 409). It now retries transient
  states; genuinely foreign-owned ones (403) can't be deleted with our key.
