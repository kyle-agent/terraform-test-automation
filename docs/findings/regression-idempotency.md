# Idempotency regression diagnosis (SCP provider)

Diagnosis only — no `apply` was run (no SCP credentials). Hypotheses are derived
from the provider schema and each scenario's `main.tf`.

- Provider: `registry.terraform.io/samsungsdscloud/samsungcloudplatformv2`, **v3.3.1**
  (resolved by `scripts/setup_provider_mirror.sh`).
- Schema source: `terraform providers schema -json` against the local mirror.
- Symptom for all four: create succeeds, but a re-plan with unchanged config
  reports changes instead of a clean no-op.

> Note on a schema limitation: `terraform providers schema -json` does **not**
> expose `RequiresReplace`/`UseStateForUnknown` plan modifiers. The
> "destroy+create" vs "in-place update" distinction below is inferred from
> attribute flags + scenario shape, not directly read from the schema.

---

## 1. samsungcloudplatformv2_vpc_vpc (scenarios/vpc_vpc)

Scenario sets: `cidr = "192.167.0.0/18"`, `name = "regr-vpc"`,
`description = "regr-test"`. No `tags`.

Suspect attributes (schema flags):
- `description` — **optional + computed**, string, API `maxLength: 50`.
- `cidr` — **required**, string, API constraints `minMask /16`, `maxMask /24`.
- `vpc` — **computed**, single nested object that mirrors the full API record
  (contains its own `cidr`, `name`, `description`, `cidrs[]`, timestamps, `state`).

Hypothesis: `description` is Optional+Computed. If the API returns a
normalized/trimmed/empty value when it does not echo the config string back
(or normalizes `regr-test`), Terraform sees config `"regr-test"` vs the
provider-returned computed value and shows a perpetual in-place diff. The
computed `vpc` nested object is also a churn risk if it is not stabilized with
`UseStateForUnknown` (it would show `known after apply` on every plan).
`cidr` is the lower-risk path (`192.167.0.0/18` is within /16–/24), unless the
API canonicalizes the network address.

Suggested fix:
- Provider: ensure the read maps the API `description` back to state verbatim;
  if the API can return a different value, drop `Computed` (make it purely
  Optional) or add `UseStateForUnknown` so the prior config value is preserved.
  Add `UseStateForUnknown` on the computed `vpc` nested object.
- Fixture workaround: pin `description` and, if needed,
  `lifecycle { ignore_changes = [description] }` as a documented mitigation.

Confidence: **medium** (Optional+Computed `description` is the classic offender,
but cannot confirm the diff direction without an apply).

---

## 2. samsungcloudplatformv2_vpc_publicip (scenarios/vpc_publicip)

Scenario sets: `description = "regr-test"`, `type = "IGW"`. No `tags`.

Suspect attributes (schema flags):
- `description` — **optional + computed**, string, `maxLength: 50`.
- `type` — **required**, string, enum `IGW | GGW | SIGW`.
- `publicip` — **computed** single nested object mirroring the API record
  (`ip_address`, `attached_resource_*`, `state`, timestamps, etc.).

Hypothesis: Same Optional+Computed `description` pattern as the VPC — the most
likely churn source: config `"regr-test"` vs a server-normalized/empty computed
value yields a perpetual in-place diff. `type` is required and enum-constrained,
so it is unlikely to drift unless the API echoes a different casing/alias. The
computed `publicip` nested object is a secondary churn risk if not stabilized.

Suggested fix:
- Provider: map API `description` straight back to state, or make it
  Optional-only / add `UseStateForUnknown`. Stabilize the `publicip` computed
  object with `UseStateForUnknown`.
- Fixture workaround: `lifecycle { ignore_changes = [description] }` (documented
  mitigation).

Confidence: **medium**.

---

## 3. samsungcloudplatformv2_security_group_security_group (scenarios/security_group_basic)

Scenario sets: `name = "regr-sg-01"`, `description = "regression test sg"`,
`loggable = false`, `tags = { tf = "terraform" }`.

Suspect attributes (schema flags):
- `tags` — **optional**, `map(string)` (NOT computed).
- `description` — **optional** (NOT computed), string.
- `loggable` — **optional**, bool, default not declared in schema.
- `security_group` — **computed** single nested object mirroring the API record.

Hypothesis: `tags` is the most likely culprit here. It is Optional and
non-computed; if the API injects server-side/default tags (or returns the map in
a normalized form), the read can surface keys the config does not set, producing
a perpetual diff on `tags`. Secondary risk: `loggable` is Optional with no schema
default — if the provider sends `false` but the API defaults/returns a different
representation, or if the computed `security_group.loggable` is plumbed back to
the top-level attribute, a boolean diff can appear. The scenario comment also
flags the rule-resource bug class (Computed + RequiresReplace without
`UseStateForUnknown`); the computed `security_group` nested object should be
checked for the same stabilization.

Suggested fix:
- Provider: on read, only reconcile tag keys present in config (or make the
  server-default-tag behavior explicit); ensure `loggable` round-trips exactly;
  add `UseStateForUnknown` to the computed `security_group` object.
- Fixture workaround: if the API always adds default tags, document and either
  include them in `tags` or `lifecycle { ignore_changes = [tags] }`.

Confidence: **medium** (tags/server-default behavior is plausible but
unverified without an apply).

---

## 4. samsungcloudplatformv2_virtualserver_keypair (scenarios/virtualserver_keypair)

Scenario sets: `name = "regr-keypair"`, `tags = { regr = "terraform" }`.

Suspect attributes (schema flags):
- `private_key` — **computed**, string.
- `public_key` — **computed**, string.
- `fingerprint`, `user_id`, `created_at` — **computed**, string.
- `type` — **computed** (string; NOT settable in config).
- `id` — **computed**, number (note: numeric id, unusual).
- `tags` — **optional**, `map(string)`.

Hypothesis: The keypair's key material is generated once at create and is never
returned again by the API on read (`private_key` in particular is typically only
available at create time). If these Computed attributes are not stabilized with
`UseStateForUnknown`, the next plan shows them as `known after apply`, and
because `private_key` cannot be re-read, this typically forces a destroy+create
(`-/+`) replacement of the whole resource. This matches the scenario comment
("if not stabilized with UseStateForUnknown(), a second plan would churn (-/+)").

Suggested fix:
- Provider: add `UseStateForUnknown` to `private_key`, `public_key`,
  `fingerprint`, `type`, `user_id`, `created_at` so the create-time values are
  retained in state and the plan stays a no-op. (`private_key` especially must
  be preserved from state, never re-read.)
- Fixture workaround: `lifecycle { ignore_changes = [private_key, public_key] }`
  as a documented mitigation if the provider cannot be changed immediately.

Confidence: **high** (write-only/create-only computed key material that is not
state-stabilized is a well-known cause of keypair replacement churn, and the
schema shows `private_key`/`public_key` as Computed).

---

## Summary

| Resource | Prime suspect | Schema flags | Confidence |
|---|---|---|---|
| vpc_vpc | `description` (+ computed `vpc` object) | optional+computed | medium |
| vpc_publicip | `description` (+ computed `publicip` object) | optional+computed | medium |
| security_group | `tags` (+ `loggable`) | optional (non-computed) | medium |
| virtualserver_keypair | `private_key`/`public_key` (key material) | computed | high |

Common root cause across all four: Computed values (top-level Optional+Computed
attributes and computed nested API-mirror objects) that are not stabilized with
`UseStateForUnknown`, plus `tags` server-default reconciliation. Highest-value
provider fix is adding `UseStateForUnknown` plan modifiers; the keypair case is
the strongest and most likely to manifest as a destroy+create.
