# green-56 regression: triage, fixes, and the LB-shard hang

Status as of 2026-06-11 (branch `claude/youthful-cray-608zi`). This is a handoff
note so the work can resume cleanly in a later session.

## 1. What happened

A scheduled "green regression" sweep (`SELECT_STATUS=green`) over the 56
known-green scenarios surfaced **6 failing scenarios** across runs **64**
(`777273c`) and **66** (`79b690c`). Re-triage classified them as follows:

| scenario | verdict | root cause |
|---|---|---|
| `directconnect_direct_connect` | **flake, now green** | intra-shard DirectConnect/VPC collision in that run; a targeted re-test PASSED. Not a defect. |
| `dns_hosted_zone` | **fixed (registry)** | needs `vpc_id` but was classified `vpc: none`, so the lane handed it the zero-UUID -> parent `dns_private_dns.connected_vpc_ids` got an invalid VPC -> 404. |
| `dns_record` | **fixed (registry)** | same as `dns_hosted_zone` (same parent `dns_private_dns` pattern). |
| `cachestore_cluster` | **broken (cannot fix offline)** | `server_type_name = "redis1v1m2"` (the provider docs example) is rejected by the platform: `400 invalid data (Server type)`. The valid value is only resolvable via the cachestore *master-data* API; there is no Terraform data source for it (only `cachestore_engine_version`). |
| `loadbalancer_lb_health_check` | **broken (fix-direction known, not safe yet)** | `400 "the chosen subnet does not contain a Load Balancer"`. See §3 — the obvious fix poisons the shared-subnet pool lane. |
| `iam_user` | **broken (provider/platform)** | `401 Unauthorized [HMAC] HMAC valid fail` on user *create* (other `iam_*` resources sign fine). Reproducible. Consistent with the pre-existing `iam_group_member` note "iam_user 401 HMAC (account perm)". |

## 2. Fixes applied on this branch

- **`dns_hosted_zone`, `dns_record`**: registry `vpc: none -> pool`. The pool
  bootstrap exports a real `TF_VAR_vpc_id`, which flows into
  `connected_vpc_ids = [var.vpc_id]`. The standalone `dns_private_dns`
  (already `vpc: pool`, green) proves the pattern. High confidence; see §4 re:
  verification.
- **`cachestore_cluster` -> broken**, **`iam_user` -> broken**: reclassified
  with precise `issues:` notes (above). Not fixable from the test repo offline.
- **`loadbalancer_lb_health_check` -> broken**: see §3. The fixture was
  reverted to its minimal (no-LB) form; the registry note records the
  validated fix-direction.

Registry totals after this work: **green 53 / broken 26 / excluded 8** (87 total).
`scripts/validate_registry.py` passes.

## 3. The LB-shard hang (important — this is the main open problem)

The fix-verification run **68** (`f4b761e`, run id `27315496017`,
`SELECT_STATUS=green SELECT_FAMILY=dns,loadbalancer`) put these five into one
pool shard `fast-1` at `MATRIX_PARALLEL=4`:

    dns_hosted_zone, dns_private_dns, dns_record,
    loadbalancer_lb_health_check, loadbalancer_lb_member

Outcome:

    panic: test timed out after 1h0m0s
      TestCapabilityMatrix/scenarios/loadbalancer_lb_member (1h0m0s)
      ... common.TFRun -> exec.CombinedOutput  (a terraform call that never returned)
    FAIL  3600.007s
    ===== capability matrix (pool: fast-1) =====
    (no matrix md produced)
    No files were found with the provided path: out/capability-matrix.json
    ... Teardown: Error Deleting subnet ... 409 Conflict (a leaked LB still in the subnet)

Mechanics, and why it matters:

1. The pool lane gives the **whole shard a single shared subnet**.
2. The first attempt at fixing `loadbalancer_lb_health_check` added an LB to its
   fixture (correct in principle — the API does require an LB in the subnet).
   That meant **two LB scenarios creating LBs in the same subnet concurrently**
   (`lb_health_check` + `lb_member`).
3. One terraform invocation (`lb_member`) then **hung for the entire 60-minute
   go-test budget**. Because the go *process* panics on timeout, the capability
   matrix is **never written**, so **every scenario in the shard loses its
   verdict** — including the dns fixes we wanted to confirm. The hung LB also
   leaked, blocking the bootstrap subnet teardown (409).

So a single hung LB scenario poisons an entire shard. The naive `lb_health_check`
fix made this worse by adding a second contending LB, which is why it was
reverted and the scenario left `broken`.

### Fix-direction for `loadbalancer_lb_health_check` (next session)

The scenario genuinely needs an LB in its subnet. To do that without poisoning
the shard, pick one of:

- **Dedicated subnet per LB scenario** — give each LB-creating scenario its own
  subnet (in the pool VPC) so concurrent LB creates don't contend, or
- **Serialized LB lane** — schedule LB-creating scenarios at `parallel: 1`
  (a `parallel`/grouping hint in `coverage/registry.yaml` consumed by
  `scripts/plan_matrix.py`), so only one LB is built at a time, or
- **Per-scenario test timeout** so one hung terraform can't consume the whole
  shard budget and discard sibling results (defense-in-depth regardless).

Also worth confirming whether `lb_member`'s hang is purely contention-induced or
a provider-side wait-loop (its issue note mentions an "EDITING stabilize-wait +
retry" path tied to patched provider #77/#85/#67). If it can hang unbounded, a
bounded retry/timeout in the fixture or harness is warranted.

## 4. Verification still owed

- `dns_hosted_zone`, `dns_record` are **green but were not re-confirmed** — run
  68's shard was poisoned by the LB hang before the matrix was written. With
  `lb_health_check` now `broken` (excluded from green sweeps), the next green
  sweep's `fast-1` shard is `dns_* + lb_member` only, which should complete and
  confirm the dns fixes naturally. If a faster signal is wanted, run a targeted
  `SELECT_FAMILY=dns` sweep.

## 5. How to re-run a targeted sweep

The pool workflow keys off the GitHub event. For a one-off targeted re-test,
temporarily pin the `push` branch of the `SELECT_*` expressions in
`.github/workflows/coverage-sweep-pool.yml` (job `plan`, "Derive matrix" step),
push to trigger, then revert the pin on the next commit (the concurrency group
is not cancel-in-progress, so an in-progress run survives the revert). Example
used here: pin push to `SELECT_STATUS=green` + `SELECT_FAMILY=dns,loadbalancer`.

Always confirm the triggered run is `in_progress` (it is the
`Coverage Sweep Pool` run for your head SHA) before pushing the revert.
