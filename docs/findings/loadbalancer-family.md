# Load balancer family — capability findings (2026-06-08)

Source runs: `27121594571` (first un-exclude) and `27122245554` (re-test after fixture
fixes). Account `9b13e0d04b7544ad8b66905cd94888bd`, region `kr-west1`, provider mirror
v3.3.2.

## Summary verdict

| scenario | verdict | blocker |
|---|---|---|
| `loadbalancer_lb_health_check` | ✅ **green** | — (full lifecycle passes) |
| `loadbalancer_basic` | broken | #77 Create-no-wait (destroy CREATING) |
| `loadbalancer_lb_server_group` | broken | apply/replan OK; destroy #77 CREATING |
| `loadbalancer_lb_listener` | broken | one-LB-per-subnet 409 (+ #77) |
| `loadbalancer_loadbalancer_public_nat_ip` | broken | one-LB-per-subnet 409 (+ #77) |
| `loadbalancer_lb_member` | broken | provider rejects computed `object_id` at plan (+ above) |
| `loadbalancer_loadbalancer_private_nat_ip` | excluded | needs an external LB id (no pool plumbing) |

## Three independent blockers found

### 1. Provider `Loadbalancer.Create` does not wait for ACTIVE (#77)
`service/loadbalancer/loadbalancer.go` issues the create call and returns immediately —
it never polls for the LB to leave `CREATING`/reach `ACTIVE`, and there is no
timeout/wait knob in the schema. The capability matrix does apply→replan→destroy with
only seconds between create and destroy, while an LB takes 1–2 min to provision, so
destroy reliably hits:

```
400 Bad Request: The loadbalancer is not in a deletable state (state: CREATING)
```

The LB then leaks and pins the pool subnet → bootstrap teardown `409`s → **pool VPC
leak** (reclaimed out-of-band by `cmd/api_reaper/sweep_all.py`). Fix must be
provider-side: Create should wait for ACTIVE (or Delete should poll until deletable).

### 2. Platform allows only ONE Load Balancer per subnet, and blocks a 2nd while the 1st is CREATING
```
409 Conflict: Cannot create a Load Balancer because the only Load Balancer under the
subnet <id> is not in ACTIVE state.
```
The coverage pool shares ONE bootstrap subnet across all `vpc: pool` scenarios and runs
the LB shard at `parallel: 4`. Because each LB scenario creates its own LB in that one
shared subnet, only the first wins; the rest 409. Combined with blocker #1 (the first LB
stays CREATING), the contention is guaranteed.

**Implication for the harness:** LB scenarios cannot be exercised in the shared pool
subnet in parallel. To get real coverage they must each run in their OWN subnet
(`vpc: self`) and/or serially (`parallel: 1`). Even then, blocker #1 prevents a clean
destroy until the provider waits for ACTIVE — so this is only worth doing once #77 is
fixed.

### 3. `lb_member` rejects a computed `object_id` at plan time
```
Missing object_id: `object_id` is required when `object_type` is `VM`.
```
The fixture wires `object_id = <backend server>.id`, which is unknown-at-plan (computed).
The provider's `ModifyPlan` validation treats unknown as missing and fails the plan,
instead of deferring the check to apply. This blocks any fixture that backs a VM member
with a server created in the same apply. Provider plan-validation bug.

## What is and isn't fixture-fixable
- **Fixed in fixtures (commit 3d1db26):** LB name collisions (scenario-distinct stems
  `rlbb/rlbl/rlbp/rlbg/rlbm`), and `lb_server_group`/`lb_member` now create their own LB
  in-subnet first (the platform requires an LB present before a server group).
- **Not fixture-fixable (provider/platform):** all three blockers above. They are filed
  in `coverage/registry.yaml` per-scenario `issues` and belong to the #77 area.

## Recommended next steps (when provider #77 lands)
1. Re-model the LB scenarios as `vpc: self` (own VPC+subnet each) OR add an LB-only lane
   that runs `parallel: 1`, so the one-LB-per-subnet limit isn't hit.
2. Re-test; with Create waiting for ACTIVE, destroy should succeed and the scenarios can
   go green.
3. For `lb_member`, if the provider still rejects computed `object_id`, split into two
   applies (server first) or pin a pre-created server id.
