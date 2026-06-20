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
| #92 | vpc_port / virtualserver_server | **Value Conversion Error** (unknown value) in the Update model — raw framework type | open | registry, dashboard |
| #96 | vpc_transit_gateway_firewall_connection | create/apply **Value Conversion Error** — the nested `transit_gateway` schema was missing `firewall_id`, so `ObjectValueFrom(model.AttributeTypes())` built a **14-key** object that failed `State.Set` against the **13-key** schema. (The prior "platform circular limit" framing was overturned — platform sequencing/the #98 waiter are fine; this was the real, provider-side blocker.) | **fixed** (PR #99, verified green) | repro sweep 27859964524 → **PR #99 adds firewall_id (14/14)** → green run **27867591203** (full lifecycle + destroy_verify ok) |
| #94 | vpc_vpc_endpoint | Create/Read/Update mapped `resource_key` from `account_id` instead of the real `ResourceKey` → state corruption + spurious replace. | **fixed (build-only)** (PR #100) | apply still blocked on obtaining a valid opaque `resource_key` (no connectable-resources data source); not runtime-verifiable yet |
| #74↝ | iam_user (Update) | in-place Update 400s **"Input should be greater than 0"** when `password_reuse_count` is unmanaged. **Root cause was API behavior, not a pure provider bug:** `UpdateIAMUser` **REQUIRES** `password_reuse_count > 0` (create allows omitting it; the SDK then sent `0` → 400). No provider/SDK change can synthesize the value — the **config must supply it**. | **resolved (fixture)** | Greened by setting `password_reuse_count = 2` in the `iam_user` fixture → full lifecycle **+ update axis ok** (run 27881799582). PR #101 (state-guard) and PR #102 (SDK `*int32`+omitempty) were detours — **now inert**; #102 merely changed the 400 to "Field required", confirming the field is mandatory. |

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
