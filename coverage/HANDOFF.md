# Coverage-expansion session handoff

**Branch:** `main` — session 2026-06-18 (v4 reconciliation). Dev branch `claude/epic-ride-9zotgp`.
**Last updated:** 2026-06-18
**Purpose:** Single source of truth for resuming the Terraform-provider coverage
expansion work in a fresh session. **Start at [`AGENTS.md`](../AGENTS.md)** (mission +
multi-agent architecture + session bootstrap), then this file, then `tasks/lessons.md`
(correction rules), then `coverage/registry.yaml`. Run `/session-start` to automate this.

---

## 0. Session 2026-06-20 (continued, LATEST) — provider fix PR #99 → firewall_connection GREEN

**Branch:** `claude/confident-carson-gnchzx` (both repos). Continued from the retest diagnosis below.

**Root cause + fix (fork PR #99 → fork `main`, sha 4e0cb9d):** the firewall_connection `Value Conversion
Error` was a schema/model mismatch. `service/vpc/transit_gateway_firewall_connection.go` builds the
computed `transit_gateway` nested object via `ObjectValueFrom(tgw.AttributeTypes(), tgw)`, but the SDK
model `TransitGateway.AttributeTypes()` returns **14** keys (incl. `firewall_id`) while the resource
schema declared only **13** (missing `firewall_id`). Once the #98 waiter reached ACTIVE, `State.Set`
rejected the 14-key value against the 13-key schema. PR #99 declares `firewall_id` (Computed) → 14/14.

**Re-retest GREEN (sweep 27867591203, build-ref=`main` carrying the fix):** `vpc_transit_gateway_firewall_connection`
→ validate/plan/apply/replan/destroy/**destroy_verify all ok** (leak-0, clean teardown).
→ **registry green 99→100; lifecycle green 64→65 (83.3%)**. #96 firewall_connection RESOLVED
(`PROVIDER_ISSUES.md` #96 → fixed/verified). Test-repo merged to `main` (PR #33, dashboard published);
fork PR #99 merged to fork `main`.

**Still open:**
- **Cascade (#96 family) — `vpc_private_nat` + `vpc_private_nat_ip` now GREEN** (sweep 27869756258, leak-0):
  rechained each to `TGW→vpc_connection→firewall_connection` (dropped the separate, broken
  `vpc_transit_gateway_firewall` resource — firewall_connection registers its own firewall), and derived
  private_nat_ip's IP via `cidrhost(private_nat_cidr,10)` so the pool lane's injected public
  `TF_VAR_ip_address` can't push it out of range → **registry 100→102, lifecycle 65→67 (85.9%)**.
  Remaining family: `vpc_transit_gateway_firewall` **now also GREEN** (sweep 27872045009, same rechain
  TGW→vpc_connection→firewall_connection→firewall, leak-0 → lifecycle 67→68). Only
  `vpc_transit_gateway_uplink_rule` left: the chain reached its create but 400'd "destination cidr should
  be included in vpc cidr blocks" → `destination_cidr` fixed to the pool VPC cidr 192.168.0.0/24 (was
  192.168.40.0/24), re-sweeping.
- **Persistent leak:** TGW `e50f2da4` + pool VPC `42b72d76` from the FAILED retest remain stranded after
  ~5h + 3 reap passes (the un-listable firewall connection blocks teardown) — now behaving like the
  permanently-stuck `rpv273154960170`; likely needs console/owner or a platform-side timeout. Account
  workable at TGW 1/3, ~3/5 VPC free. The GREEN re-retest itself left NO new leak (destroy_verify ok).

---

## 0. Session 2026-06-20 — TGW firewall_connection retest (diagnosis; superseded by the fix above): #96 is a PROVIDER bug, not a platform dead-end

**Branch:** `claude/confident-carson-gnchzx` (this repo). Resumed via `/session-start`. The prior
handoff's "Task A" (vpc_transit_gateway_rule + cachestore_cluster) was already GREEN (done in 0b) — a
stale note. User approved spending one TGW-pool sweep to retest `vpc_transit_gateway_firewall_connection`.

**Result — firewall_connection retest (sweep 27859964524, pool lane, build-ref=fork `main`):**
- ✅ **#96 "platform circular limit" fully OVERTURNED.** With the rechained fixture
  (TGW→vpc_connection→firewall_connection) + the patched 12-min waiter, the create got PAST every
  platform precondition (old INACTIVE, then "needs a connected VPC"). validate ✅ plan ✅ **apply ❌**.
- ❌ **New blocker = PROVIDER bug.** apply fails `Value Conversion Error … Expected framework type from
  provider logic … This is always an error in the provider` at firewall_connection.regr (main.tf:46) — a
  terraform-plugin-framework type mismatch in the firewall_connection Create/Read **state model** (same
  class as #92, on the create path). firewall_connection stays **broken**; the path forward is a PROVIDER
  fix, not fixture/waiter work.
- ⚠️ **Teardown trap + leak (NOT yet reclaimed — needs a follow-up reaper pass).** Partial-create cleanup
  400s "Firewall Connection must be disconnected before all VPC connections can be deleted" → the retest's
  TGW `e50f2da4` (regr-tgwfwca0f3ea) + bootstrap pool VPC `42b72d76` (rpv278599645240) leaked. **Two reap
  passes (27860555251, 27861502444) did NOT clear them:** the Value-Conversion partial-create left a
  firewall connection that does NOT appear in the firewall-connections LIST yet still blocks the
  vpc_connection delete (400) → TGW + VPC 409. Precedent (reap-before TGW 984b8825) cleared only on a pass
  ~hours later, so this just needs a FOLLOW-UP reaper pass once it settles (not an emergency).

**Recorded this session:** registry `vpc_transit_gateway_firewall_connection` untested→broken w/ the new
diagnosis; `docs/PROVIDER_ISSUES.md` #96 row corrected (+ #92 row added); dashboard merged
(coverage.json / COVERAGE.md / docs/index.html — lifecycle green unchanged **64**); `tasks/lessons.md`
TGW entry rewritten. **Posted the correcting finding as a comment on fork #96** (the platform-limit
framing there is now superseded by the provider Value Conversion Error — no need to re-post). **Account (final):** reap-before (27859481902) cleared the older regr-tgwfwc TGWs;
after the retest + 2 reap passes, **TGW `e50f2da4` + pool VPC `42b72d76` remain stranded** (settling, see
above) alongside the permanently-stuck VPC `rpv273154960170` (subnet a7793ccc, 2026-06-11 dbaas leak) →
**TGW 1/3, 3 of 5 VPC free** (workable, not leak-0).

**NEXT:**
1. **Provider fix (axis ①):** patch fork `service/vpc/transit_gateway_firewall_connection.go` Create/Read
   state mapping for the Value Conversion Error (identify the mismatching attribute — pull the full error
   from sweep 27859964524 pool-job step 7). Source-build, re-retest firewall_connection; if green, cascade
   the vpc_connection prereq to firewall / uplink_rule / private_nat[_ip].
2. **Decide (outward, needs steer):** file a NEW fork issue for the Value Conversion Error, or comment the
   correction on #96 (it currently claims a platform-limit story now disproven).
3. **Follow-up reaper (leak):** fire api-reaper again next session to reclaim TGW `e50f2da4` + pool VPC
   `42b72d76` once the stuck firewall connection settles (precedent ~hours). Live Pages dashboard
   publishes from `main` only; this session's dashboard delta is in-branch until a merge/PR.

## 0. Session 2026-06-19c — provider fixes: vpc_cidr GREEN + TGW #96 myth overturned

**Branch:** `claude/pensive-goldberg-e34mtm` (both repos). Continued from 0b below.
**Provider fork PR #98 → fork main (MERGED, sha 8a1b4bb):** two fixes for the dev team.

- ✅ **vpc_cidr → GREEN (registry 98 → 99; lifecycle green 63 → 64)** via PROVIDER fix #60.
  `vpc_cidr.go` Delete now treats the unmapped-DELETE 403 ("Action definition is not found")
  as a graceful state-only removal (Warning) — the secondary CIDR is reclaimed when the VPC is
  deleted. Verified live: run **27812898493** (build-ref=fork branch) apply/replan/destroy ok.
- 🔧 **TGW firewall family — `#96` "platform circular limit" OVERTURNED.** `transit_gateway_
  firewall_connection.go` waiter was the real problem: it accepted only ATTACHING→ACTIVE on the
  shared 120-min `WaitForStatus`, erroring instantly on INACTIVE. Patched to a **bounded 12-min**
  `StateChangeConf` tolerating ATTACHING/INACTIVE. With a connection-first fixture, the create
  got **past** the old INACTIVE error and 400d **"There must be at least one connected VPC to
  proceed"** (run 27812898493) → the true chain is **TGW → vpc_connection → firewall_connection
  → firewall**, NOT a firewall-circular dead-end. Fixture rechained (vpc:pool) accordingly.
  **NEXT:** retest `vpc_transit_gateway_firewall_connection` (now broken, fixture ready,
  build-ref back to `main` which has the waiter fix); if ACTIVE, cascade the same vpc_connection
  prereq to `vpc_transit_gateway_firewall`, `_uplink_rule`, `vpc_private_nat[_ip]` (#96 family).
- Build-ref reverted to `main` (fork main now carries both fixes). dbaas-probe default already
  back to `cleanup`. api-reaper fired for the probe's stranded TGW (run after 19feca9).

---

## 0b. Session 2026-06-19b — TGW-rule + cachestore GREENED (registry 96 → 98)

**Branch:** `claude/pensive-goldberg-e34mtm` (off main @ PR #30 merge). Resumed via `/session-start`.
**PR #31 → main (MERGED):** dashboard + 2 greens. Pages publishes from main on merge.

**Done — TWO scenarios greened (registry green 96 → 98; coverage.json lifecycle green 61 → 63):**
- ✅ **vpc_transit_gateway_rule → GREEN** (run **27801651607**): validate/plan/apply/replan/
  destroy/destroy_verify all `ok`; pool teardown clean (7 destroyed, no 409, zero TGW leak).
  Confirms fork **#95** (create-202 tolerates omitted `created_at`, recovers id via list+match).
  Gates pre-flip: build-ref=fork `main` has #95; api-reaper **27801131713** = 0 TGWs (cap free).
- ✅ **cachestore_cluster → GREEN** (run **27804355967**): full lifecycle `ok`, destroy_verify=ok
  (leak-0). Two stacked blockers, both fixed:
  1. **Engine/server-type IMAGE MISMATCH (#83).** DBaaS-Probe `catalog` run **27802022018**
     (read-only) showed redis1v2m4 IS in the 70-type catalog — not a missing name. cachestore has
     2 engine versions, "Valkey Sentinel 8.1.4" (first non-EOS) + "Redis OSS Sentinel 7.2.11";
     server-types carry product_image_type (Valkey→css*, RedisOSS→redis*). Fixture auto-picked
     Valkey but hardcoded redis1v2m4 → reject. Fix (commit 5e22958): derive server_type_name from
     the chosen engine version's product_image_type (no hardcoded id).
  2. **sentinel_port 26379 → 26378.** After (1), apply reached cluster-create then failed
     "Provider produced inconsistent result after apply: sentinel_port was 26379, now 26378". The
     platform's expected sentinel port is 26378 (the provider schema's own documented example);
     26379 (conventional Redis) was echoed back as 26378. Fix (commit 6a9685a): set 26378. The
     first failed retest (run 27802519587) leaked a partial cachestore cluster → api-reaper
     **27803881583** cleared it before the green retest.

**Done — housekeeping:**
- Dashboard built: `build_coverage.py` merged both matrices → coverage.json + COVERAGE.md
  (lifecycle green 63). dbaas-probe.yml push default reverted `catalog` → `cleanup`.

**Account state:** 1 long-standing stuck VPC `rpv273154960170` (subnet a7793ccc…, a 2026-06-11
dbaas dependent-probe leak; reaper 409s, can't clear with current key) → 4 of 5 VPC quota free.

**Provider observation (not yet filed):** cachestore `sentinel_port` is Required but the platform
fixes it to 26378 — provider could mark it Optional+Computed so users don't have to guess. Minor UX.

**Lessons added (tasks/lessons.md):** scenarios/** push triggers a sweep (bundle fixture+flip);
cachestore server_type must match engine-version product_image_type.

---

## 0. Session 2026-06-19 — per-resource agent fleet → engineering wave + serial sweep pipeline

**Method:** orchestrator + 7 parallel role agents (one per greenable FAMILY, not per
resource — families share a root cause). Agents did engineering only (patch + fixture +
local build/validate + fork issue); they did NOT commit/push or trigger CI. Orchestrator
consolidates + serializes the account-touching sweeps under the 5-VPC quota.

**Provider patches (fork `claude/epic-ride-9zotgp`, commit 93a2ae5, combined `go build` PASS):**
- **dns** `service/dns/{private_dns,hosted_zone,record}.go` — wait-for-gone on Delete (async
  202 must finish before return; VPC binding releases only when private_dns is gone). **#93**.
- **vpc/vpcpeering.go** — stop deriving/sending `approver_vpc_name` (response-only field; API
  create never accepts it); schema Computed-only. **#61** (prior fix was directionally WRONG).
- **vpc/vpc_transit_gateway_rule.go** — tolerate create-202 omitting server-set `created_at`
  (SDK model wrongly required); recover id by list+match. **#95**.
- **iam/user.go** — `account_id` Required + validator + default to caller acct, replacing the
  opaque 401 "[HMAC] HMAC valid fail". **#74** (IAM trio reclassified: provider-fixable, NOT
  an account boundary or HMAC race — both disproven).

**Test-repo (commit ea95260):** TGW family (6) fixtures gained firewall+firewall_connection
prereq chains; IAM 3 fixtures pass account_id (`TF_VAR_account_id` already injected all lanes);
`vpc_vpc_peering_approval`→**excluded** (cross-account); `cmd/dbaas_probe/probe.py` +leak-0
`catalog`/`cachestore-servertypes` modes; `docs/domain/*` (dns, vpc-peering, tgw-private-nat,
dbaas) + `domain.yaml` curated; **build-ref main→claude/epic-ride-9zotgp** (source-builds the patch).

**Issues:** #61/#74/#93/#95/#96 + NEW #94 (vpc_vpc_endpoint connectable-resources/Read bug) +
comments on #60 (vpc_cidr graceful-Delete) / #82 (platform-500 cluster). Triage confirmed the
hard-blocked set stays broken/excluded (backup#80, budget/cert/dns_public_domain/lb_listener#82).

**SERIAL SWEEP PIPELINE (orchestrator drives; only the family-of-interest is `untested` at push):**
1. **IAM ×3** (vpc:none, leak-0) — IN FLIGHT run **27798318949** (push ea95260). Expect green.
2. **DNS** (dns_hosted_zone, dns_record; vpc:pool, LEAK-RISK) — flip 2→untested, reap before/after.
3. **Peering** (vpc_vpc_peering[_rule]; vpc:self, multi-VPC leak-prone) — isolated, reap before/after.
4. **TGW Batch A** (firewall, firewall_connection, uplink_rule — vpc:none, ≤3 TGW) then **Batch B**
   (transit_gateway_rule, private_nat, private_nat_ip — vpc:pool). A and B NOT concurrent (3-TGW cap); reap between.
5. **DBaaS**: dispatch *DBaaS Probe* `engines=catalog` (read-only, leak-0) → harvest live
   `server_type_name`; pin into cachestore fixture → flip cachestore_cluster→untested→sweep.
   searchengine/sqlserver stay broken (platform provisions FAILED; api-test never reached RUNNING).
**Per VPC-touching family: push api-reaper (SWEEP_ALL=1) before AND after; confirm quota clear
before trusting reds (quota-cascade red = environmental).** Flip registry green ONLY on a real
clean-lifecycle matrix. Heavy families may span multiple sessions — this list is the resume point.

**RESULTS (this session, registry green 89 → 96, +7):**
- ✅ **IAM ×3 GREEN** (run 27798318949, novpc leak-0): iam_user, iam_user_policy_bindings,
  iam_group_member — #74 fix (account_id Required+default) + account_id fixtures.
- ✅ **DNS ×2 GREEN** (run 27798451467, pool, teardown clean = #93 fixed): dns_hosted_zone,
  dns_record — validate/plan/apply/replan/**update**/destroy all ok, no VPC leak.
- ✅ **Peering ×2 GREEN** (run 27799716751 selfvpc, destroy_verify=ok = leak-0): vpc_vpc_peering,
  vpc_vpc_peering_rule — #61 rework (drop response-only approver_vpc_name from create body) works.
- ❌ **TGW Batch A ×3 still broken** (run 27799716751 novpc): firewall, firewall_connection,
  uplink_rule all `400 "firewall connection state INACTIVE"` — the firewall_connection never
  reaches ACTIVE before the dependent firewall create. PLATFORM state-machine (#96), not
  provider/fixture-fixable in one apply. apply-fail left TGW partial-creates → api-reaper fired after.

**STILL TODO (lower-confidence / lower-value, not yet swept):**
- `vpc_transit_gateway_rule` — blocker (#95 created_at decode) is INDEPENDENT of the firewall
  ACTIVE issue; provider fix is in. Worth ONE isolated pool sweep (needs TGW + vpc_connection only).
- `vpc_private_nat`, `vpc_private_nat_ip` — same ACTIVE-firewall-connection blocker as Batch A;
  do NOT expect green until the platform ACTIVE precondition is solvable. Keep broken.
- `cachestore_cluster` — dispatch *DBaaS Probe* `engines=catalog` (read-only, leak-0) to harvest a
  live `server_type_name`, pin into the fixture, then one pool sweep. searchengine/sqlserver stay
  broken (platform provisions FAILED).

---

## 0. Session 2026-06-18 — v4.0.0 reconciliation + coverage reality check

**v4.0.0 reconciliation (upstream released v4.0.0; we test our patched v3.3.x+fixes):**
- Tested the **released v4.0.0 binary** (`SCP_PROVIDER_SOURCE_BUILD=0`/`VERSION=4.0.0`,
  branch-only; reverted to `=1` patched mode after). v4 SDK is private → can't build v4.
- **v4 fixed only 4 of ~60 issues** → closed #59/#25/#71/#89. v4's real wins: **ImportState on
  37 resources** (we had 1; empirically 10 scenarios import=ok) + ~13 validators.
- **Labels on the fork** (single-query hand-off): `v4-must-fix` (12 P0), `v4-still-lacks` (45,
  all provider-fixable lacks), `fix-verified-green` (7, ready patches).
- **Deliverables:** `docs/V4_RECONCILIATION.md` (full), `docs/V4_MUST_FIX.{md,html,txt}` (P0
  hand-off) — **published**: https://kyle-agent.github.io/terraform-test-automation/V4_MUST_FIX.html

**Coverage reality check (broken→green is mostly tapped out):**
- registry: **green 89 / broken 24 / excluded 8**; coverage.json strict lifecycle-green **54/79**.
- Most broken are **hard-blocked** (platform-500, account-perm, cross-account — see lessons).
- **peering #61 fix is INEFFECTIVE** (re-test 27736779212 on a confirmed patched build still
  400s "no value given for approver_vpc_name"). peering reverted to broken.
- VPC quota was exhausted by leaks → reaped clean (run 27737291663). Quota free now.

**NEXT (greenable broken needs real engineering — pick one):** (a) rework provider #61
auto-resolve in fork `vpcpeering.go` → peering green + a verified patch; (b) DBaaS #83
fixtures (searchengine/sqlserver — create ACCEPTED, self-contained, low leak risk);
(c) TGW family fixture ordering (private_nat/transit_gateway_firewall — depends_on/wait,
complex + multi-VPC leak-prone). Multi-VPC tests: isolate + reap before/after (lessons).

---

## 0. Session 2026-06-17 (LATEST) — update/import axis + harness skills

**Shipped (PR #26 → main, live dashboard published):**
- **update axis 4 → 23 ok**, **import 22 unsupported** (#81/#4). 22 `update.tfvars` authored
  by 3 parallel subagents (in-place description/tags, verified non-RequiresReplace + Update
  PATCHes), merged from sweep `27666766466`. Lifecycle green **54** (honest, see dns below).
- **Harness skills adopted** (`.claude/skills/`, force-tracked like scp-api): `session-start`,
  `session-checkpoint`, `retro` + new **`tasks/lessons.md`** (12 correction rules).
- **provider#92** filed: vpc_port + virtualserver_server Update "Value Conversion Error
  (unknown value)" (raw type in Update model). vpc_subnet update 400 "IP not valid".

**Truth-ups / open issues:**
- **dns_hosted_zone + dns_record → broken** (were stale-green). Were mis-classified `vpc:none`
  despite `needs:[vpc_id]` → fixed to `vpc:pool`; apply/replan/update then pass but **destroy
  409s and LEAKS the bootstrap pool VPC** (dns_private_dns.parent stays attached). Leaked VPC
  was reaped (api-reaper, 4 resources). LEAK-RISK: do not blindly re-sweep these. Root cause of
  the destroy 409 (provider Delete bug vs platform propagation timing) NOT yet pinned — the
  exact per-resource delete error wasn't captured; needs a guarded re-run before filing an issue.
- **cachestore_cluster** still broken: `redis1v1m2`/`redis1v2m4` both 400 "(Server type)" —
  needs a live cachestore server-type catalog lookup (no provider data source).

**In-flight at handoff:** 3 parallel subagents authoring `update.tfvars` for ~26 more
lifecycle-green resources (loadbalancer/directconnect, iam/vpn/misc, dbaas/filestorage/ske).
NEXT: consolidate their output → flip to untested → run update sweep (cheap families first;
DBaaS/loadbalancer are heavy) → merge → publish. Known no-in-place-update (skip): cachestore
n/a, certificate_manager_self_sign, network_logging_storage, servicewatch_log_stream,
vpc_subnet_vip_port (Update is a no-op / fully immutable).

---

## 0X. Session 2026-06-13 (LATEST) — data-source read-smoke layer + dashboard split

**Branch:** `claude/zen-pasteur-1e38be` (test repo). **Question that started it:** are the
"복수개 생성" (plural) entries worth testing separately? **Finding:** the provider has NO
count/for_each-style "make N of the same resource" resources — `count`/`for_each` is pure
Terraform core and reuses the single-create provider path (proven: identical code path; the
real failures there are platform quotas like TGW-max-3, iam-key-max-2, already caught by the
single-create scenarios). The ~90 plural NAMES on the old dashboard were all **list data
sources**, which the dashboard wrongly counted in the 191 "resource" denominator. They are a
DIFFERENT code path from the singular read (separate `*_datasources.go`, list vs show API), so
single-resource green did NOT cover them — but they're read-only and cheap.

**What changed:**
- **`scripts/gen_ds_smoke.py`** (NEW) — scans the provider source for the family grouping and,
  authoritatively, consumes a `terraform providers schema -json` dump (`--schema`) for the exact
  required-args (a regex-only scan misses the 4 data sources built via a delegated
  `resp.Schema = XxxSchema()` helper: baremetal_baremetal, filestorage_volume,
  multinodegpucluster_gpunode, quota_account_quota). Emits `coverage/provider_surface.json`
  (the new authoritative surface: **87 resources + 168 data sources**, replaces
  `resource_families.json`) and **34 `scenarios/ds_<family>/` read-only smoke fixtures** (a bare
  `data` block per standalone-readable data source; 3 use a documented const arg —
  network_logging resource_type, ske_nodepool_images type).
- **Disposition:** 127 data sources standalone-readable (smoke-covered, registry `untested`,
  vpc:none); **41 excluded** (require a parent-resource id/arg — exercised implicitly by the
  resource scenarios, not testable standalone).
- **`build_coverage.py` / `build_coverage_html.py`** — funnel denominator is now the **87 managed
  resources** (was a conflated 191). Data sources get their own section/table: read-verified
  (the `ds_<family>` scenario's plan is green) vs excluded. fully-green resources unchanged at
  **37/87** (was reported as 37/191).
- **Local verification:** built the provider from fork `main` (vendored SDK, `go build`), all
  **34 ds_* scenarios `terraform validate` green** via dev_overrides. Live plan/read needs API
  creds → runs in CI.
- **CI:** pushing the registry change fires `coverage-sweep-pool` with `SELECT_STATUS=untested`,
  which now selects ONLY the 34 ds_* scenarios (novpc lane, read-only, leak-0). After the sweep,
  merge `out/capability-matrix.json` with `build_coverage.py` and commit to light up the data-
  source reads on the dashboard (same manual merge pattern as before — no auto-commit job exists).
- **Provider build ref fix:** `coverage-sweep-pool.yml` `SCP_PROVIDER_BUILD_REF` was the deleted
  `claude/wonderful-keller-h05ucp`; repointed to fork `main` (PR #90 merged there).
- Regenerate after any provider-surface change: `terraform providers schema -json > s.json &&
  python3 scripts/gen_ds_smoke.py --schema s.json`, then `build_coverage.py` + `_html.py`.

---

## 0Y. Session 2026-06-12 — domain-knowledge-driven fixes, green 56→57+, #83 cracked for eventstreams

**Branch:** `claude/wonderful-keller-h05ucp` (all 3 repos; provider branch == fork main b5b7197).
**Method:** multi-agent — inspection (registry/non-green triage), domain research (api-test-automation
`data/api_docs.json` = scraped FULL API request schemas + `validated-facts`), provider audit (fix presence
+ open issues), plus implementation agents (peering probe, dbaas probe extension).

### Sweep run 27399112864 results (no leaks; all teardowns clean)
- **eventstreams_basic → GREEN** (#83 CRACKED): the bare 400 value_error was THREE fixture defects found
  via the scraped API schema: (1) cluster `name` pattern is `^[a-zA-Z]*$` — the old default `regr-evs`
  hyphen was rejected; (2) `akhq_enabled=true` without akhq creds/node group is an invalid topology → off;
  (3) v1.1 create requires `service_watch_log_collection`. Full lifecycle green.
- sqlserver_cluster: `license=""` (was a retail key) got PAST the parse error → now named 400
  **"Invalid Engine Version"** (data-source first-non-EOS id rejected) → dbaas_probe `sqlserver-versions`
  mode iterates all ids.
- searchengine_cluster: named 400 **"Invalid License"** → dbaas_probe `searchengine-license` mode
  iterates omitted/""/null/OPEN_SOURCE/BASIC/ENTERPRISE.
- vpc_cidr: Delete impl (vpc 1.2) now reaches the API — 403 changed from "Action definition is not
  found" to **"You do not have permission to Action"** = endpoint EXISTS, key lacks the IAM action.
- vpc_private_nat_ip: serialized retest still 400 "TGW not in Connectable state" — same platform
  state-machine constraint as vpc_private_nat (Connectable = ACTIVE TGW firewall connection).

### Key domain knowledge mined from api-test-automation (USE THIS)
- `data/api_docs.json` (1372 endpoints, 2306 models) holds the full request schemas incl. required
  flags + patterns + enums — this is what cracked #83. `data/api_bodies.json` = doc-template bodies.
- **vpc_peering**: the API suite got create **202** with body {requester_vpc_id, approver_vpc_id,
  approver_vpc_account_id, name, description, tags:[]} — NO approver_vpc_name — and approval body
  `{"type":"CREATE_APPROVE"}` (400 while CREATING; retry). Provider sends `description: null` always
  (SDK NullableString constructor bug), omits tags, header `Scp-API-Version: vpc 1.1`.
  → `cmd/peering_probe/` bisects 6 variants (a-f) to isolate the 400 trigger (#61).
- subnet create has `type` enum **GENERAL|LOCAL|VPC_ENDPOINT** → vpc_vpc_endpoint fixture now creates
  its own VPC_ENDPOINT-type subnet 192.168.0.64/27 in the pool VPC (flip → untested).
- certificate_manager's "platform 500" happened sending placeholder PEM; API suite proves cert creation
  works → fixture now generates real self-signed PEM via hashicorp/tls (flip → untested).
- dns_public_domain_name: deliberately NOT retried — a successful create registers a REAL paid domain
  with NO delete API.

### Mid-session addendum (2026-06-12 ~08:40)
- **peering residual 400**: with the provider null-description fix live, both peering scenarios STILL
  fail "no value given ... approver_vpc_name" (run 27402349483) -> cause = fixtures passed a SYNTHETIC
  approver_vpc_name mismatching the real approver VPC name (probe variant b with the CORRECT name
  parsed fine). Fixtures now omit it (provider derives from id); retest pending. The failed applies
  left half-created peerings pinning 4 VPCs; reaper run 27403108300 deleted 12 resources but several
  VPCs still 409 - one pinned subnet (a7793ccc...) belongs to a STALE pool VPC `rpv273154960170`
  leaked by an earlier session AND is being used by the in-flight dbaas probe. Re-reap after.
- **vpc_vpc_endpoint progress chain**: ENDPOINT-type subnet ok -> reserved-IP ok (.70) ->
  "Resource Key is not valid : 1.1.1.1" -> retry with real OBS IP 112.107.105.22 pending.
- **dbaas probe v2** (fixture-mirror bodies, fdc0076): sqlserver iterates all 20 engine ids;
  searchengine iterates 5 versions x {omitted,null} license. Run (push d77ec3b) in_progress ~30min
  = almost certainly a 202 (CREATING-trap wait before self-delete). Harvest its log for the
  winning combination, then pin the fixtures accordingly.
- searchengine string licenses ("", OPEN_SOURCE, ...) are SCHEMA-rejected; omitted/null reach the
  named InvalidLicense check -> license validity is engine-version-dependent.

### In-flight / next
- Push of this commit triggers: coverage sweep (certificate_manager novpc + vpc_vpc_endpoint pool),
  peering-probe (2 VPCs, leak-0), dbaas-probe (`sqlserver-versions searchengine-license`; flip the
  workflow run arg back to `cleanup` after). Read those run logs, apply verdicts to the registry.
- Remaining broken after this wave = permission (vpc_cidr destroy, iam×2, loggingaudit,
  filestorage_replication), platform (TGW family ×4 + private_nat ×2, lb_listener 500-104,
  dns/budget/backup 500, peering ×3 pending probe), DBaaS ×2 pending probe.

---

## 0Z. Session 2026-06-09/10 — provider-fix verification, green 41→56

**Branch:** `claude/youthful-cray-608zi` (BOTH repos). **Resume:** read this section first.
**Result:** registry green **41 → 56 (+15)**. All work committed+pushed on the branch in both
repos; **pending consolidation to `main` via PR** (same pattern as PR #14).

### Provider fixes (fork `kyle-agent/terraform-provider-samsungcloudplatformv2`, branch above)
Built+verified end-to-end via source-build (`SCP_PROVIDER_SOURCE_BUILD=1`,
`SCP_PROVIDER_BUILD_REF=claude/youthful-cray-608zi`; vendored SDK under `third_party/` + go.mod
`replace` → tokenless `go build`). Issues with a verified-green test carry the GitHub label
**`fix-verified-green`** (filter: `label:fix-verified-green`):
- **#75** iam_role (CreateRole policy_ids `[]` not null) → iam_role, iam_role_policy_bindings GREEN
- **#77** loadbalancer Create wait-ACTIVE / Delete wait-gone → loadbalancer_basic, lb_server_group, public_nat_ip GREEN
- **#67/#85** virtualserver_server needs state=ACTIVE / lb_member object_id → lb_member GREEN
- **#58** iam_access_key Delete disables an enabled key first → iam_access_key GREEN (after quota freed)
- **#59** vpc_subnet dns_nameservers `[]string`→`types.List` → vpc_subnet GREEN
- **#76** TGW status-waiter no longer hangs → vpc_transit_gateway, vpc_transit_gateway_vpc_connection GREEN
- vpc_publicip Read → v1.2 ShowPublicip (SUBNET enum) → vpc_subnet_vip_nat_ip GREEN
- lb_member/lb_server_group destroy-ordering (EDITING stabilize + retry) → lb_member clean destroy
- **#60** vpc_cidr Read implemented (idempotent) — but Delete has NO server API (403 "Action definition is not found"); destroy still fails. Commented on #60.
- **#61** vpc_vpc_peering: provider now serializes `approver_vpc_name` correctly (proven: local json.Marshal emits it; remote SDK patched) BUT API still 400 "no value given … Invalid error data" → **API-side**, not provider. Commented on #61. peering ×3 stay broken.

### Non-provider GREENs this session
- virtualserver_volume (#69 tag was STALE — fixture size already ÷8; just needed a re-test)
- **virtualserver_image (#86)** — OBS image URL must be the **account-namespaced path form**:
  `https://object-store.kr-west1.e.samsungsdscloud.com/{account_id}:terraform-vmimage-test/<key>.qcow2`
  (plain bucket path → OBS `NotFoundBucketNameInPath`; virtual-hosted → no public DNS). Staging step
  now builds `${TF_VAR_obs_endpoint}/${SCP_ACCOUNT_ID}:terraform-vmimage-test/<key>`. Commented on #86.

### KEY platform constraints / gotchas discovered (save for future sessions)
- **TGW account max = 3.** "Failed to create a Transit Gateway due to exceed the maximum size(3)."
  Running >3 TGW-creating scenarios concurrently fails. TGW sub-resources (firewall, firewall_connection,
  uplink_rule) additionally require an **ACTIVE TGW firewall connection** first (multi-step state machine);
  private_nat needs the TGW in **Connectable** state (a created vpc_connection alone is NOT enough).
  These TGW-family scenarios remain broken — fixtures are valid (terraform validate ok) but the
  platform state-machine + 3-TGW cap make them hard; not a provider bug.
- **OBS path addressing = `{account_id}:{bucket}`** (account-namespaced). Buckets `terraform-vmimage-test`
  (image) + `regr-obs-*` (sweepable). Reaper now also reaps orphaned **IAM access keys** (test desc
  `regr-access-key` only; NEVER the live `SCP_ACCESS_KEY` — see `reap_access_keys` in sweep_all.py).
- **iam_access_key** caps at 2 keys/principal; an orphaned enabled key (pre-#58 bug) blocked it until the
  reaper reclaimed it. `_client.py` gained a `put` method for the disable-before-delete.
- **vpc_vpc_peering / vpc_transit_gateway_rule** fail with the same "no value for required property
  (approver_vpc_name / created_at) … Invalid error data" pattern = **API-side**, provider sends it.

### Remaining broken = platform/account/API (NOT provider-fixable)
Platform 500/ISE: backup(#80), budget/certificate/dns_public_domain(#82), loadbalancer_lb_listener
(500 code 104 — re-testing), vpc_vpc_endpoint, DBaaS eventstreams/searchengine/sqlserver(#83).
Account-perm: iam_group_member, iam_user_policy_bindings, loggingaudit_trail, filestorage_replication.
API-side: peering×3(#61/#84), tgw_rule(created_at). Platform-dep: vpc_cidr Delete, TGW firewall family,
private_nat×2, virtualserver_image needs operator OBS (now resolved).

### Dashboard note (IMPORTANT for "reflect on dashboard")
`docs/index.html` is rendered by `scripts/build_coverage_html.py` from **`coverage/coverage.json`**
(per-stage results), NOT from `coverage/registry.yaml`. `coverage.json` is updated by
`scripts/build_coverage.py <capability-matrix.json>` (merges a RUN's matrix) and is currently STALE
(Jun 8). To make the dashboard show this session's greens: re-run the fixed scenarios, then
`build_coverage.py` the resulting matrices into `coverage.json`, commit → `pages.yml` publishes.

---


**Done this session:**
- **Account cleanup** (user: "stop all tests + delete all resources"). No cron exists;
  nothing auto-runs. Extended the API reaper (`cmd/api_reaper/sweep_all.py`) and ran it
  repeatedly until the account is clean from our key's reach:
  - ServiceWatch log groups: added paginated bulk-delete; cleared all our-key-owned ones.
  - DBaaS cluster `400 InvalidServiceState` (mid-create/terminate): fixed via
    retry-with-backoff → clusters delete and release their pinned subnets/VPCs.
  - Block storage volumes: found at `virtualserver` host **`/v1/volumes`** (not
    `/v1/block-storages`); deleted 13. Also added eventstreams/vertica/gpu clusters,
    server-groups, custom images (test-prefix-guarded), backup, gslb sweeps.
  - **Final state:** core infra (VPC/subnet/server/SG) empty. Remaining = **403
    permission-boundary only**: 2 SCF log groups + backup/gslb/baremetal/gpu services
    our key has no rights on + ~5 stale lb-health-checks (400). These need the account
    owner/console or an IAM grant — the reaper can do no more with the current key.
- **Persistent multi-agent + domain-knowledge architecture** authored (so any session
  continues identically): `AGENTS.md`, `docs/agents/*`, runnable subagents in
  **`.claude/agents/*`**, `coverage/domain.yaml` + `docs/domain/*`,
  `docs/PROVIDER_VERIFICATION.md`, `docs/PROVIDER_ISSUES.md`.

**Branch consolidation (2026-06-08):** this session's work was merged to **`main`**
(PR #14) and every `claude/*` scratch branch in this repo was deleted — `main` is now
the single source of truth; new sessions branch from it. (The session token couldn't
delete branches itself — `403`; deletion was done manually.)

**Resume next session by:** reading `AGENTS.md` → this §0 → `docs/roadmap.md`. The
coverage-expansion TODO is unchanged (see §5 below): firewall_firewall_rule self-contain,
iam_role_policy_bindings, vpc_vpc_endpoint, the LB ×7 decision, virtualserver_image via
OBS. Pre-existing leaker decisions already recorded in §4/§6.

---

## 0a. Session 2026-06-08 (coverage continuation, branch `claude/youthful-cray-608zi`)

Worked the §5 TODO via 5 parallel agents (fixtures only; registry flips batched
centrally to respect the **VPC quota = 5**). All fixtures pass `terraform validate`
against provider mirror v3.3.1.

**Fixtures authored (committed, no account impact):**
- `firewall_firewall_rule` → **self-contained**: creates own VPC+subnet+IGW
  (`firewall_enabled=true`) and wires `firewall_id` from the IGW's computed
  **nested** attr `internet_gateway.firewall_id`. Lane pool→**self**.
- `iam_role_policy_bindings` → self-contained (own iam_role + iam_policy).
- `vpc_vpc_endpoint` → schema-correct OBS endpoint (resource_type=OBS,
  endpoint_ip_address `192.168.0.12` inside pool /27).
- `loadbalancer_*` (7) → all schema-valid + dependency-wired + #77 note. Ready to
  un-exclude once an always-reap is in place (see `docs/findings/loadbalancer-reap-strategy.md`).
- `virtualserver_image` → parameterized + `scripts/upload_image_to_obs.py` +
  `docs/findings/virtualserver-image-obs.md`. **Stays blocked** pending a real
  image upload test in CI.

**Batch-1 coverage sweep — run `27120875200` (VPC-safe: ≤1 concurrent VPC):**
- `firewall_firewall_rule` → ✅ **GREEN** (validate→apply→replan→destroy→destroy_verify
  all ✅, 238s; self-containment confirmed working, no leak).
- `iam_role_policy_bindings` → ❌ **broken**: apply fails at `iam_role` create with
  `400 'Input should be a valid list'` — this is **#75** (iam_role create is itself
  broken; `iam_role` scenario is also #75-broken). Blocked-by-dependency, not a
  fixture defect. The concrete 400 message is a fresh diagnostic for #75.
- `vpc_vpc_endpoint` → ⊘ **not exercised**: pool bootstrap `terraform init` hit a
  **transient `504 Gateway Timeout`** fetching provider v3.3.2 from GitHub (mirror
  download 504 → direct-registry fallback also 504). NOT a fixture/quota/leak issue
  (init failed before any resource → **no VPC leaked**). Left `untested` and
  re-pushed to retry (only vpc_vpc_endpoint re-runs).

**vpc_vpc_endpoint retry (run 27121247070):** apply ❌ `400 'VPC Endpoint Type Subnet
not found'` even with a REAL pool subnet_id → **platform/AZ limitation**, not a fixture
defect. Marked **broken** (blocked-with-findings). Teardown clean, no leak.

**Batch 2 = loadbalancer family (run 27121594571, 6 pool LB scenarios, 1 shard):**
- `loadbalancer_lb_health_check` → ✅ **GREEN** (full lifecycle).
- 5 failed on FIXTURE issues (now fixed by an agent, commit WIP 3d1db26):
  (a) **LB name collision** — all scenarios in a shard share one `TF_VAR_name_suffix`,
  so `rlb${suffix}` collided across scenarios (`...name(rlb4d39a5) already exists`).
  Fix: scenario-distinct short stems (`rlbb/rlbl/rlbp/rlbg/rlbm`). (b) `lb_server_group`
  & `lb_member` need an **LB already in the subnet** — fix: each now creates its own LB
  first (+depends_on). (c) `lb_member` plan failure was a cascade of (b), object_id
  wiring was already correct.
- **`loadbalancer_basic` → broken (#77, provider Create-no-wait):** apply/replan OK but
  destroy `400 not in a deletable state (CREATING)` — provider `Loadbalancer.Create`
  returns before ACTIVE and has no wait knob, so quick create→destroy leaks the LB →
  pinned the pool subnet → **subnet/VPC 409 leak**. Reaper run **27121999759** reclaimed
  the leaked subnet `8a65f4…`+VPC `b3c1ae…` (`sweep_all done: 5 deleted`) → account clean.
- **Re-test (run 27122245554) — fixtures fixed but 3 provider/platform blockers remain;
  see `docs/findings/loadbalancer-family.md`:**
  - `lb_server_group` → apply ✅ replan ✅ **destroy ❌** (#77 CREATING leak).
  - `lb_listener`, `loadbalancer_public_nat_ip` → **apply ❌ 409** "only Load Balancer
    under the subnet is not in ACTIVE state" = **ONE-LB-per-subnet** limit; the shared
    pool subnet at `parallel: 4` makes LB scenarios collide.
  - `lb_member` → **plan ❌** provider rejects a COMPUTED `object_id` (backend server.id,
    unknown-at-plan) when `object_type=VM` (plan-validation bug).
  - All 4 marked **broken** with precise per-scenario `issues`. The `lb_server_group` LB
    leaked → reaper re-fired (run after commit 06fb1cc) to reclaim subnet/VPC.

**Provider #77 + 2 sibling blockers gate the LB family** (documented in
`docs/findings/loadbalancer-family.md`): (1) Create doesn't wait for ACTIVE → CREATING
destroy leak; (2) one-LB-per-subnet vs shared-pool-parallel; (3) lb_member computed
object_id rejected at plan. Net LB result: **lb_health_check green; the other 6 broken/
excluded** with provider-actionable diagnostics. To make them green later: re-model LB
scenarios as `vpc: self` (own subnet) + serial, AND land the #77 Create-wait fix.

**`virtualserver_image` — probed & characterized (broken/blocked):** wired the novpc lane
to upload a tiny real **CirrOS** qcow2 to OBS and pass its URL. The probe nailed the
platform image-import contract in 3 iterations — **URL must end `.qcow2`** (fixed via OBS
`--key`), **os_distro in allow-list** (`cirros`→**`ubuntu`** fixed), and **a fetchable OBS
URL**. Final blocker: the OBS test key **cannot create buckets**
(`ForbidCreateBucketException`, run 27124795518), so staging fails and the dummy URL is
used. This is a permission boundary (cf. §8). Resume: supply a pre-existing writable OBS
bucket via `--bucket`/`OBS_BUCKET` (helper now reuses an existing bucket) — see
`docs/findings/virtualserver-image-obs.md` "Probe results".

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

### Reaper coverage expanded (commit 695afbc) + final cleanup state
Per user request ("delete block storage + all other resources"). Added sweeps:
- **block storage volumes** — found at **`virtualserver` host, `/v1/volumes`**
  (NOT `/v1/block-storages`, which 403s). Last run deleted **13** leaked volumes
  (202). baremetal-blockstorage/`/v1/block-storages` 403 (no perm/none).
- eventstreams / vertica / multinodegpucluster clusters (same /v1/clusters +
  retry). `multinodegpucluster` 403 (not enabled for our key).
- virtualserver server-groups + custom images (images guarded to test-prefix
  names so base/public OS images are never deleted).
- backup (`/v1/vaults`,`/v1/backup-policies`) and gslb (`/v1/gslbs`,`/v1/gslb`):
  all **403** for our key.
- **Final state:** the account-id probe returned `unknown/empty` (no
  VPC/subnet/server/SG left) — core infra is CLEANED. Everything our reaper key
  can reach is deleted. **Remaining = 403 permission-boundary only:** 2 SCF log
  groups (`/scp/scf/regrscf*`, owned by SCF principal `bc371a79…`), plus the
  backup/gslb/baremetal/gpu services our key has no rights on, and ~5 stale
  `lb-health-checks` that 400. These need the **account owner / console**, or an
  IAM grant giving the reaper key (`2a579fc…`) delete rights on ServiceWatch/SCF/
  backup/gslb. The reaper itself can do no more with the current key.

## 0c. Session 2026-06-09 — provider #77 fixed, built, and proven (LB greens)

Pivoted to **fixing the provider** (the dominant coverage blocker). Key arc:

- **SDK build blocker solved.** The public provider depends on the PRIVATE
  `terraform-sdk-samsungcloudplatformv2` module (404 without org access; the fork has no
  GH_ACCESS_TOKEN). The operator supplied the SDK; it is **MIT-licensed**, so it was
  **vendored in-repo** at `third_party/terraform-sdk-samsungcloudplatformv2/` (trimmed to
  *.go+go.mod, ~61MB) with a `go.mod replace`. Now `go build ./...` works with **no token**
  (fixes provider #50). Provider `build-check` CI is green.
- **#77 fix implemented** in `service/loadbalancer/loadbalancer.go` (provider repo,
  branch `claude/youthful-cray-608zi`): `Create` waits for ACTIVE (new
  `waitForLoadbalancerStatus`, mirrors vpngateway) then re-Reads; `Delete` waits until the
  LB is gone before returning (so dependent subnet delete doesn't 409). Compiles locally + CI.
- **Harness runs the PATCHED provider.** `scripts/setup_provider_mirror.sh` gained a
  `SCP_PROVIDER_SOURCE_BUILD=1` mode: it clones the fork (`SCP_PROVIDER_BUILD_REF`) and
  `go build`s the provider into the filesystem mirror instead of downloading the release.
  Enabled via env in `coverage-sweep-pool.yml`. (Keep ON to retain the LB greens; the
  released provider lacks #77.)
- **Result (run 27212070186, patched provider):**
  - `loadbalancer_basic` -> **GREEN** (full lifecycle, clean destroy, no leak).
  - `loadbalancer_lb_server_group` -> **GREEN** (full lifecycle).
  - `loadbalancer_loadbalancer_public_nat_ip` -> apply/replan OK (IGW fixture fix worked);
    **destroy 409** — publicip "not deletable (ATTACHED)" + LB "associated resources":
    a destroy-ordering gap (public NAT / publicip detach not awaited). Next provider fix.
  - `loadbalancer_lb_listener` -> **apply 500 ISE** "Failed to create listener (code 104)"
    (after session_duration_time + routing_action fixture fixes) — platform-side; timebox.
  - Fixture fixes committed: lb_listener `routing_action=LB_SERVER_GROUP` + `session_duration_time=120`;
    public_nat_ip adds an IGW (+depends_on).

**Pipeline proven end-to-end:** provider source fix -> vendored tokenless build -> source-built
mirror -> coverage sweep -> green. The remaining 22 provider-blocked scenarios (#76 TGW ×7,
#75 iam ×2, #59/#60/#67/#69/#74/#82/#85 …) can be unblocked the same way: patch the provider
on this branch, the source-built mirror picks it up, re-test.

**Resume:** confirm reaper run after 27212070186 reclaimed the lb_listener/public_nat leaks;
then either (a) fix the next provider bug (e.g. public_nat destroy-ordering, or #76 TGW), or
(b) retry lb_listener (transient 500?). Source-build stays enabled in coverage-sweep-pool.yml.
