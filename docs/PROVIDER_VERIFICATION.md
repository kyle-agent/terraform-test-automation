# Axis ① — Provider verification method

How we judge the `samsungcloudplatformv2` Terraform provider as an independent third
party and drive fixes. Owned by the
[Provider-Verification agent](agents/provider-verification-agent.md) (with
API-Evaluator and Issue-Registrar). Confirmed defects live in
[`PROVIDER_ISSUES.md`](PROVIDER_ISSUES.md).

## Inputs we trust
1. **Provider source** (the fork) — for static analysis.
2. **Real execution** — the capability matrix (`make matrix` /
   `coverage-sweep-pool.yml`) running apply/replan/destroy on the dedicated account.
3. **SCP Open API ground truth** — via the API-Info-Collector, the `scp-api` skill,
   and `cmd/dbaas_probe` (to separate *provider bug* from *platform behaviour*).
4. **Benchmark conventions** — how mature providers (AWS/Azure) behave (idempotency,
   computed-value stabilization, import support, predictable destroy).

## The four checks
### a. Static analysis
Read the provider Go source for known failure classes (catalogued as the **Deep
Audit**, see [`docs/test-catalog.md`](test-catalog.md)): missing `UseStateForUnknown`
on computed attributes, absent/!infinite ACTIVE waiters, panics (empty-list indexing,
map type assertions), missing `ImportState`, non-uniform timeouts, delete
idempotency, 404 string-matching.

### b. Dynamic analysis
Run the lifecycle and read behaviour: idempotency churn on replan (`AssertNoChanges`),
spurious replacement (`AssertNoReplacement`), panics, leaks on destroy, opaque errors,
and infinite hangs. The capability matrix records every stage per resource.

### c. Cross-check vs the API
When a scenario fails, confirm against the raw API whether the platform accepts the
same request (e.g. DBaaS bodies via `cmd/dbaas_probe`). If the API accepts what the
provider rejects/mangles, it's a provider-mapping bug; if the API itself refuses, it's
platform behaviour (record in domain knowledge, not as a provider bug).

### d. Third-party assessment
The [API-Evaluator agent](agents/api-evaluator-agent.md) grades developer experience
and systemic themes (e.g. "no ImportState anywhere", "DBaaS hides field errors") that
single tests miss.

## Classification (every red result)
- **Provider defect** → reproduce, record in `PROVIDER_ISSUES.md`, file on the fork,
  add a regression test (1 test ↔ 1 defect; `docs/adding-tests.md`).
- **Platform / quota / permission (BLOCKED)** → record as domain knowledge; not a bug.
- **Test-fixture bug** → fix the scenario.

## Issue registration (to the fork)
One issue per defect with reproduction (scenario + plan diff / error body / source
line) and the regression-test `IssueRef`. The report pipeline
(`scripts/publish_report.sh`) auto-reopens a sub-issue when its regression fails again.
See the [Issue-Registrar agent](agents/issue-registrar-agent.md).

## Continuous provider sync
- The provider is consumed from a **mirror** (GitHub releases, registry is blocked):
  `scripts/setup_provider_mirror.sh`, currently pinned **v3.3.2**.
- On a new release: bump the mirror version, re-run the matrix + regressions, and
  update each issue's status in `PROVIDER_ISSUES.md` (fixed / still-broken /
  **regressed**). A fixed defect's regression test must go green before the issue is
  closed.
