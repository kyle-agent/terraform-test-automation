# Lessons

Correction rules and recurring patterns for this project, so a fresh session does
not re-discover the same trap. Loaded by `/session-start`; appended by `/retro` and
`/session-checkpoint`.

**Format** — one entry per lesson:

```
### <specific, searchable title>
- trigger: <the concrete situation that should fire this lesson>
- do: <the action to take instead>
- conf: high|med|low · seen: YYYY-MM-DD · obs: <count>
```

`conf` = confidence (high = proven repeatedly; low = one observation). `obs` =
times observed. Update `seen`/`obs` when re-encountered instead of duplicating.
A lesson without a concrete trigger + action is not a lesson — delete it.

---

### Key coverage.json by scenario name, never the matrix `resource` field
- trigger: merging a `capability-matrix.json` into `coverage/coverage.json` (build_coverage, or a one-off driver).
- do: key the store by the SCENARIO name (identity for 82, +4 aliases `*_basic`/`securitygroup_rule_basic`, `ds_*` as-is, skip `import_smoke`). The matrix `resource` field is the FIRST resource declared in the .tf (`scenarioResource()` in matrix_test.go), which for self-contained scenarios is a prerequisite — e.g. firewall_firewall_rule/vpn_vpn_tunnel report `resource=vpc_vpc`. build_coverage was fixed to do this; keep it.
- conf: high · seen: 2026-06-17 · obs: 2

### A sweep's RED can be a stale provider build-ref, not a real regression
- trigger: a resource the registry calls green shows up as plan-only/fail on a fresh sweep, and `SCP_PROVIDER_SOURCE_BUILD=1`.
- do: confirm `SCP_PROVIDER_BUILD_REF` points at a branch that actually contains the fix BEFORE trusting the red. The 2026-06-12 sweep built from a DELETED branch and silently knocked vpc_subnet/vpc_transit_gateway back to plan-only; they were green again once the ref was valid.
- conf: high · seen: 2026-06-17 · obs: 1

### "lifecycle green" is create→replace→destroy, NOT full CRUD
- trigger: reporting a resource as "fully green" / quoting the headline coverage number.
- do: say "lifecycle green" — it is validate→plan→apply→replan→destroy only. `update` (in-place Update handler; needs `update.tfvars` + `MATRIX_UPDATE=1`) and `import` (ImportState; `MATRIX_IMPORT=1`, unsupported on most resources, #81) are separate axes tracked on the dashboard.
- conf: high · seen: 2026-06-17 · obs: 1

### DBaaS replan=skip on the dashboard came from a probe, not the matrix
- trigger: a DBaaS cluster (cachestore/epas/mariadb/mysql/postgresql) shows apply+destroy ok but replan=skip and is registry-green.
- do: to record replan and make it lifecycle-green, re-run it through the STANDARD capability matrix (it always replans). Heavy/slow/pool — shard under the 5-VPC quota. (Wave-2 confirmed epas/mariadb/mysql/postgresql idempotent; cachestore needs a server_type fixture refresh.)
- conf: high · seen: 2026-06-17 · obs: 1

### billing_planned_compute apply is a real 1-year billing reservation
- trigger: tempted to flip billing_planned_compute to untested / run it through apply.
- do: keep it excluded (reason: cost). Creating it commits a real multi-year reservation. The provider #78 fix is `stringvalidator.OneOf("01","03","05")`; the API enum is `01/03/05` (1/3/5-year) — `YEAR_1`/`1-year` are display names and are rejected.
- conf: high · seen: 2026-06-17 · obs: 1

### The live dashboard publishes from main only
- trigger: user says the live GitHub Pages dashboard is stale after I pushed to a claude/** branch.
- do: `pages.yml` triggers on push to `main` only. Branch commits update `docs/index.html` in git but NOT the live site. Merge the branch to main (PR) to publish; pages.yml regenerates index.html from coverage.json on deploy.
- conf: high · seen: 2026-06-17 · obs: 1

### Re-merge old matrices via the Actions artifact API instead of a fresh sweep
- trigger: the dashboard is stale because a past green sweep was never merged into coverage.json, and the run is < 90 days old.
- do: `mcp__github__actions_get download_workflow_run_artifact` → presigned blob URL → `curl` the zip → unzip `capability-matrix.json` → re-key by scenario → merge with the run's REAL timestamp (not now()) so most-recent-wins is preserved. No account/sweep needed.
- conf: high · seen: 2026-06-17 · obs: 1

### Poll CI run status via MCP, not unauthenticated bash curl
- trigger: waiting on a coverage-sweep / pages run to finish.
- do: the shared egress IP rate-limits api.github.com (403) for unauthenticated requests. Use `mcp__github__actions_get`/`actions_list` (authenticated) to check status, or a Monitor poll that tolerates 403s. Do not rely on bash `curl` to api.github.com for a definitive status.
- conf: med · seen: 2026-06-17 · obs: 1

### Edit registry.yaml with the yaml library, not line-based mutation
- trigger: bulk-flipping many registry.yaml entries' status/issues in one pass.
- do: load with `yaml.safe_load`, mutate the dict, re-dump with `yaml.safe_dump(sort_keys=True, default_flow_style=False, width=100)` (the documented canonical style). A line-based loop that does `lines[j:k]=...` while iterating shifts later indices off a pre-computed block map → it silently set the *issues* but not the *status* on 2 of 22 entries. yaml round-trip is the safe path (it also normalizes drifted hand-edits).
- conf: high · seen: 2026-06-17 · obs: 1

### A scenario with needs:[vpc_id] must be vpc:pool, never vpc:none
- trigger: a scenario whose fixture references var.vpc_id (directly or via a prereq like dns_private_dns.parent connected_vpc_ids) is classified vpc:none in registry.yaml.
- do: set vpc:pool so the pool lane bootstraps a VPC and injects TF_VAR_vpc_id. vpc:none runs the novpc lane with NO bootstrap, so var.vpc_id defaults to the zero-UUID (00000000-...) and the create 404s. dns_hosted_zone/dns_record were mis-set to vpc:none despite needs:[vpc_id] and failed reproducibly until moved to pool (dns_private_dns, the same prereq, was correctly vpc:pool).
- conf: high · seen: 2026-06-17 · obs: 1

### The capability-matrix note can hide the real destroy error
- trigger: a scenario shows destroy=fail but you need the exact provider delete error to file an issue.
- do: don't burn a re-run hoping to capture it — the matrix runner mis-prioritizes the note (it showed an "import unsupported" line for a destroy-failed row) and does NOT put the terraform destroy stderr in the note or job stdout. The raw delete error is unrecoverable from artifacts/logs. Diagnose from the downstream symptom instead (e.g. the bootstrap VPC 409 'Cannot terminate due to associated resources' that a leaked child causes) and file on that evidence. dns_private_dns destroy-leak -> fork #93. (A runner fix to surface destroy stderr would remove this blind spot.)
- conf: high · seen: 2026-06-17 · obs: 1

### vpc_vpc_peering greens by DROPPING approver_vpc_name from the create body (#61 RESOLVED)
- trigger: working vpc_vpc_peering / vpc_vpc_peering_rule, or reading the old "auto-resolve is ineffective" note.
- do: the fix is NOT to populate approver_vpc_name — it is to STOP sending it. api_docs `POST /v1/vpc-peerings` (VpcPeeringCreateRequest) has only {name, requester_vpc_id, approver_vpc_id, approver_vpc_account_id, description?, tags?}; approver_vpc_name is response-only. The reworked vpcpeering.go sets ApproverVpcName=types.StringNull() (schema Computed-only) → create body matches the API → run 27799716751 GREEN, destroy_verify=ok (leak-0). The earlier auto-resolve fix (vpcpeering.go:207-220) was directionally wrong. peering + peering_rule are now green (vpc:self, same-account auto-activates ~16min each).
- conf: high · seen: 2026-06-19 · obs: 1

### TGW firewall family stays broken — firewall_connection never reaches ACTIVE in one apply
- trigger: tempted to sweep vpc_transit_gateway_firewall / _firewall_connection / _uplink_rule / vpc_private_nat[_ip] expecting a fixture depends_on chain or a provider waiter to green them.
- do: don't burn the sweep. Even with the patched provider + an in-fixture firewall + firewall_connection prereq chain (depends_on), the firewall create 400s "Transit Gateway Firewall connection state is not Active (INACTIVE)" (run 27799716751). The connection does not transition ATTACHING→ACTIVE within the apply, so every firewall-dependent resource (firewall, uplink_rule, private_nat Connectable) fails. Platform state-machine limit (#96), confirmed across sessions — NOT provider/fixture-fixable in a single terraform apply. apply-fail leaves TGW partial-creates → reap after. The ONLY independently-greenable TGW scenario is vpc_transit_gateway_rule (#95 created_at decode, needs only TGW+vpc_connection).
- conf: high · seen: 2026-06-19 · obs: 1

### Two different VPC lanes can share ONE sweep cycle under the 5-VPC quota
- trigger: serializing per-family validation sweeps and wanting to cut wall-clock cycles.
- do: scenarios in DIFFERENT lanes run as separate concurrent jobs (novpc / pool / selfvpc) and only the pool+selfvpc lanes consume bootstrap/self VPCs. A vpc:none family (e.g. TGW Batch A, 0 VPCs) can be flipped untested in the SAME push as a vpc:self family (e.g. peering, 4 VPCs) — total ≤5, and the novpc job finishes fast (~7min) while selfvpc runs long (~33min for 2× peering ACTIVE waits). Just respect cross-cutting account caps (TGW max=3). Saved a full cycle on run 27799716751.
- conf: med · seen: 2026-06-19 · obs: 1

### The fork #61 vpc_vpc_peering auto-resolve fix is INEFFECTIVE (superseded — see RESOLVED above)
- trigger: historical — kept for context.
- do: superseded by the "greens by DROPPING approver_vpc_name" lesson (2026-06-19). The auto-resolve approach was abandoned.
- conf: high · seen: 2026-06-18 · obs: 1

### Most of the broken set is hard-blocked — don't burn sweeps re-testing them
- trigger: looking to raise coverage by flipping broken -> green.
- do: triage first. The realistically-greenable broken are few; the rest are NOT provider/fixture-fixable: platform-500 ISE (backup_backup, budget_budget, certificate_manager, dns_public_domain_name, loadbalancer_lb_listener), account-permission (iam_user, iam_user_policy_bindings, iam_group_member), cross-account (vpc_vpc_peering_approval needs a 2nd account to approve). Greenable candidates need real engineering: provider fixes (peering #61) or fixture ordering (TGW family) or DBaaS engine fixtures (searchengine/sqlserver #83). Don't blind-sweep the whole broken set.
- conf: high · seen: 2026-06-18 · obs: 1

### Multi-VPC scenarios leak and exhaust the 5-VPC quota — test in isolation + reap
- trigger: testing vpc_vpc_peering / any scenario that creates 2+ VPCs, or running a big sweep after prior runs.
- do: a failed peering partial-create leaves both VPCs (terraform cleanup 409s "Cannot terminate due to associated resources"), and these stack with prior sweep leaks until "400 number(5) of VPCs exceeded" cascades onto every VPC-dependent scenario. Test multi-VPC scenarios alone, push-trigger api-reaper (SWEEP_ALL=1) before AND after, and confirm quota is clear before reading reds (a quota-cascade red is environmental, not a real defect).
- conf: high · seen: 2026-06-18 · obs: 2

### A scenarios/*.tf push triggers a coverage-sweep — bundle fixture + registry flip in ONE commit
- trigger: editing a scenario fixture and a registry status flip in separate commits/pushes while a sweep is queued.
- do: coverage-sweep-pool.yml's push paths include `scenarios/**` (not just registry.yaml), so a fixture-only push fires a sweep with SELECT_STATUS=untested = whatever is CURRENTLY untested. On 2026-06-19 a cachestore fixture-only push re-ran the still-untested vpc_transit_gateway_rule (a wasted ~24min pool cycle) ahead of the intended cachestore run. The group is cancel-in-progress:false so runs QUEUE (no overlap/leak), but you pay a full redundant cycle. Land the fixture change and its registry status flip in the SAME commit so the single triggered sweep selects exactly the scenario you fixed. Don't cancel the stray run once it is past "Bootstrap pool VPC" — mid-apply cancel leaks the scenario's resources (e.g. a TGW) and the bootstrap VPC.
- conf: high · seen: 2026-06-19 · obs: 1

### cachestore server_type_name must share the chosen engine version's product_image_type
- trigger: cachestore_cluster (or any DBaaS cluster) 400 "invalid data (Server type)"; tempted to think the server-type name is absent from the catalog.
- do: it is an ENGINE/SERVER-TYPE IMAGE MISMATCH, not a missing name. dbaas_probe catalog harvest (run 27802022018) showed redis1v2m4 IS in the live 70-type cachestore catalog. cachestore has 2 engine versions — "Valkey Sentinel 8.1.4" (first non-EOS) and "Redis OSS Sentinel 7.2.11" — and every server-type carries a product_image_type ("Valkey Sentinel" -> css*, "Redis OSS Sentinel" -> redis*). A redis* type against a Valkey engine version (or vice-versa) is rejected. The cachestore engine-version data source exposes product_image_type on contents[*], so derive the server-type family from the chosen engine version (commit 5e22958) instead of hardcoding — robust to catalog order and to either version being retired. The api_docs server-type response being empty is why this wasn't visible statically; the live catalog dump is the source of truth.
- conf: high · seen: 2026-06-19 · obs: 1
