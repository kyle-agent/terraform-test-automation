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

---

## 4. Batch-1 run results — run `27095226766` (commit 137282e)

All 4 jobs green at orchestration level. Per-scenario verdicts:

| scenario | lane | verdict |
|---|---|---|
| `vpn_vpn_gateway` | self | ✅ **GREEN** — validate→apply→replan→destroy→destroy_verify all ✅ |
| `vpn_vpn_tunnel` | self | ✅ **GREEN** — all stages ✅ |
| `servicewatch_log_stream` | none | ✅ green (log_group + log_stream apply/replan/destroy ✅) |
| `loadbalancer_basic` | pool | ⚠️ applied, but **pool subnet teardown 409'd** (leak) |
| `vpc_private_nat_ip` | pool | ⚠️ ran in same pool shard; leaker identity TBC (see below) |

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

> **CONFIRM IN NEW SESSION:** which of `loadbalancer_basic` / `vpc_private_nat_ip`
> leaked. Strong prior: `loadbalancer_basic` (issue #77 — LB destroy leak). Read
> **API Reaper run `27106727666`** (commit 38921bf) — its sweep log names every
> deleted resource: `rlb*` = loadbalancer (→ `loadbalancer_basic` leaked),
> `regr*`/nat = private nat ip (→ `vpc_private_nat_ip` leaked). That run also
> **reclaimed the leaked pool VPC** (subnet→VPC). Verify it finished `success`.

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
