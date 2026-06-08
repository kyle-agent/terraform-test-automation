# Load balancer lane: always-reap strategy (provider #77)

## Problem

Provider issue **#77 (LB destroy-leak)**: load balancers APPLY and REPLAN
cleanly, but `terraform destroy` leaks the LB (it is the confirmed leaker via
`loadbalancer_basic`). A leaked LB then **pins the pool subnet/VPC**: the pool
bootstrap teardown fails with **409 Conflict** because the subnet/VPC still has a
child LB attached. This blocks every `vpc:pool` LB scenario from running cleanly
and is why the 6 LB sub-resource scenarios are currently excluded.

All 7 LB scenarios are `vpc:pool` except `loadbalancer_loadbalancer_private_nat_ip`
(`vpc:none`). Each scenario now stands on its own — it creates the LB plus the
sub-resources it covers (server group, listener, member + backend server, public
NAT IP) — so when un-excluded each one will leak its own LB on destroy.

## Recommended approach: option (c) — always-reap after the pool shard

After the LB pool shard finishes (apply/replan/destroy of all LB scenarios), and
**before** the pool bootstrap (subnet/VPC) is torn down, run the API reaper to
delete any leaked LBs. The reaper deletes the LB sub-resources and the LB itself
via the Open API (paths the provider's broken destroy can't complete), so the
pool VPC is no longer pinned and bootstrap teardown succeeds instead of 409-ing.

This keeps the LB scenarios in-pool (cheap shared bootstrap) while neutralizing
the #77 leak at the boundary where it actually hurts — bootstrap teardown.

## How the reaper already deletes load balancers

`cmd/api_reaper/sweep_all.py` (step 4, "loadbalancers") does exactly the
dependency-ordered teardown #77 needs:

1. Delete LB children first, since an LB returns 409 while it still has them:
   it iterates `lb-listeners`, `lb-server-groups`, `lb-health-checks` and
   `DELETE`s each by id (`/v1/<collection>/<id>` on the `loadbalancer` service).
2. Then it lists `/v1/loadbalancers` and deletes each LB with a **409-aware
   retry loop** (up to 6 attempts, `sleep(20)` between 409s), accepting
   200/202/204/404 as success and then `wait_gone()` polling until the LB is
   actually gone (240s timeout, 15s interval).

Resource matching is name-prefix scoped (`rlb` is the LB test prefix; LB
scenarios name resources `rlb*`/`rsg*`/`rls*`/`rhc*`/`rmb*`), gated by
`is_test()` / `old_enough()` and the `SWEEP_ALL` account guard, so a sweep can't
touch non-test resources.

Because the reaper already tears down LB children before the LB and tolerates the
409 churn, the LB lane needs no new deletion logic — only the **ordering**: run
the reaper (LB step) after the LB shard and before pool-bootstrap teardown.

## Status

This note is design-only. The actual CI wiring (invoking the reaper's LB step
between the LB pool shard and the pool-bootstrap teardown) is a separate change
and is intentionally **not** made here. Once wired, the 6 excluded LB
sub-resource scenarios can move from `excluded` to active in the LB pool lane,
with `loadbalancer_basic` remaining the known #77 leak canary.
