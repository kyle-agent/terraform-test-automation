# Provider issues — confirmed defects & status (axis ①)

Consolidated, cross-session registry of `samsungcloudplatformv2` provider defects
found by this project. Owned by the
[Provider-Verification](agents/provider-verification-agent.md) +
[Issue-Registrar](agents/issue-registrar-agent.md) agents. This is the durable record;
the GitHub issues on the fork are the actionable copies.

> Status legend: **open** (confirmed, unfixed) · **fixed** (verified on a synced
> release) · **regressed** (was fixed, broke again) · **blocked-verify** (can't fully
> verify on current account/permissions).
> `#NN` = issue on the fork `kyle-agent/terraform-provider-samsungcloudplatformv2`.

## Behavioural / lifecycle defects (from real execution)

| # | Resource / area | Symptom | Status | Evidence / source |
|---|---|---|---|---|
| #58 | iam_access_key | create/lifecycle defect | open | registry `issues:` |
| #59 | vpc_subnet | post-deploy "requires" churn | open | TEST_STRATEGY.md |
| #60 | vpc_cidr | replan not idempotent | open | TEST_STRATEGY.md |
| #69 | virtualserver_volume | lifecycle defect | open | registry |
| #75 | iam_role | create/lifecycle defect | open | registry |
| #76 | vpc_private_nat / TGW | status-waiter **infinite hang** on transitional states | open | TEST_STRATEGY.md |
| #77 | loadbalancer | create does **not wait for ACTIVE** → destroy leaks the LB → pool VPC unreclaimable | open (confirmed) | reaper run 27106727666 deleted 2 leaked LBs |
| #79 | dns private-dns | destroy returns **409** | open | scp-api SKILL |
| #81 | **all resources** | **no `ImportState`** → terraform can't adopt/clean leaks (reaper compensates via API) | open (systemic) | scp-api SKILL |
| #82 | dns public-domain-name | create returns **500 but leaves the resource**; no delete API → orphan | open | scp-api SKILL |
| #83 | **DBaaS family** | weak client-side validation; provider **drops the API error body** → `400 value_error` names no field | open (systemic) | cmd/dbaas_probe/FINDINGS.md |

## Idempotency / schema defects (from `docs/findings/regression-idempotency.md`)

| Resource | Suspect | Root cause | Confidence | Suggested provider fix |
|---|---|---|---|---|
| vpc_vpc | `description` + computed `vpc` object | optional+computed value churns vs server-normalized | medium | `description` Optional-only / `UseStateForUnknown` on `vpc` |
| vpc_publicip | `description` + computed `publicip` object | same pattern | medium | map API value back verbatim / `UseStateForUnknown` |
| security_group_security_group | `tags` (+ `loggable`) | server-default tags → perpetual diff | medium | reconcile only config-present keys / `UseStateForUnknown` |
| virtualserver_keypair | `private_key`/`public_key`/`fingerprint` | computed key material not stabilized → "known after apply" → replace | **high** | `UseStateForUnknown` on key material |

Common theme (API-Evaluator systemic finding): **computed values not stabilized with
`UseStateForUnknown`**, plus server-default reconciliation on `tags`.

## Platform / permission BLOCKED (not provider bugs — for context)
- DBaaS **CREATING-trap** (~15–20 min non-deletable) — platform behaviour; record in
  domain knowledge, not as a defect.
- Permission boundaries on our key (`403`/`401`): scf, backup, gslb, baremetal,
  multinodegpucluster, iam_user, loggingaudit.

## Maintenance
- Add a row the moment a defect is **reproduced** (not before).
- When syncing a new provider release, re-verify each open row and update Status;
  move fixed→ (keep history) and flag any **regressed**.
- Keep `coverage/registry.yaml` `issues:` fields and `coverage/domain.yaml`
  `known_issues:` in sync with this table.
