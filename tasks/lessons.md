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
