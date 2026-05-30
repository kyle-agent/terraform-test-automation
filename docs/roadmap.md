# Roadmap — autonomous execution to the final goal

This file is the single source of truth for the end goal and remaining work, so
execution can continue across context resets without re-asking.

## Final goal (definition of done)

1. Every SCP provider resource (87/87) is exercised by the **capability matrix**
   (`make matrix`) across validate → plan → apply → replan → destroy.
2. Resources that genuinely fail in `MODE=integration` are **auto-tracked as
   issues** (already wired) with the concrete diff captured.
3. The 78 AUTO-GENERATED placeholder fixtures are progressively **promoted to
   hand-written, realistic integration scenarios** (valid values, real
   dependencies via TEST_* ids) — starting with the families most likely to be
   exercised, and at minimum every resource that can be created without scarce
   prerequisites.
4. Everything runs unattended on the 6-hour schedule; failures surface as issues.

## Status snapshot

- main: dynamic pipeline, 87/87 schema coverage, 6h integration schedule,
  provider mirror (PRs #1–#4 merged).
- PR #7 (observability): capability matrix + diff-capturing auto issue reporting.
- Known real regressions (issue #6): vpc_vpc, vpc_publicip,
  security_group_security_group, virtualserver_keypair — re-apply not idempotent.

## Work breakdown (parallelizable units)

Units are file-disjoint so multiple agents can run concurrently without
conflicts. Each agent validates its scenarios against the real provider mirror
before finishing.

- **WB-1 Diagnose known regressions** (issue #6): for each of the 4 failing
  resources, capture the exact `terraform plan` diff after apply and classify
  (RequiresReplace? unstable computed default? normalized attribute?). Output:
  docs/findings/*.md + issue #6 update. (No scenario file changes.)
- **WB-2 Promote VPC/network family**: hand-write realistic scenarios for
  vpc_*, security_group_*, firewall_* (owns scenarios/vpc_*, scenarios/security_*,
  scenarios/firewall_*).
- **WB-3 Promote compute/storage family**: virtualserver_*, filestorage_*,
  baremetal_* (owns those scenario dirs).
- **WB-4 Promote DB/analytics family**: mysql/postgresql/mariadb/sqlserver/epas/
  vertica/cachestore/searchengine clusters (owns those scenario dirs).

Promotion = replace placeholder values with schema-valid realistic values, wire
external deps via TEST_* (documented in config/env.example), keep
`terraform validate` green, and add/adjust an integration idempotency test where
a clean lifecycle is feasible.

## Guardrails

- Never weaken an assertion to make a test pass; a real provider bug stays a
  failing test + an issue.
- Every scenario must pass `terraform validate` via the provider mirror before commit.
- Keep PRs focused per work-breakdown unit.
