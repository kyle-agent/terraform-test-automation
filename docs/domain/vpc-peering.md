# VPC peering domain knowledge

Companion prose for `coverage/domain.yaml › services.vpc_peering`. Schema source:
`api_docs.json` endpoints `networking/vpc/*vpcpeering*`. Behavioural facts cite the
probe/run/issue that proved them.

> Confidence: schema = confirmed (Open API ref); same-account rule = confirmed (peering
> probe 27401023616); provider mismatch = confirmed (run 27736779212, issue #61).

## 1. Lifecycle & ordering
```
requester_vpc (self) ─┐
approver_vpc  (self) ─┴─ vpc_peering (POST /v1/vpc-peerings)
                            ├─ approval  (PUT /v1/vpc-peerings/{id}/approval)   ← cross-account only
                            └─ routing_rule (POST /v1/vpc-peerings/{id}/routing-rules)
```
Needs **two VPCs** → self-lane, and burns 2 of the 5-VPC quota. Destroy: routing-rules
→ peering. Cross-account delete also goes through the approval state machine
(`DELETE_APPROVE`).

## 2. Create body — `POST /v1/vpc-peerings` (model `VpcPeeringCreateRequest`)
| field | req | type | notes |
|---|---|---|---|
| `name` | **REQ** | string | Pattern `^[a-zA-Z0-9-]*$`, len 3–20 |
| `requester_vpc_id` | **REQ** | string | the requesting VPC |
| `approver_vpc_id` | **REQ** | string | the approver VPC |
| `approver_vpc_account_id` | **REQ** | string | approver's **account** id (same as requester's for same-account) |
| `description` | opt | string\|null | |
| `tags` | opt | array[Tag] | |

**There is NO `approver_vpc_name` field in the create body.** The create body takes
exactly the four required fields above. `requester_vpc_account_id`, `approver_vpc_name`,
`requester_vpc_name`, `account_type` etc. are **response-only** (read-back) fields on the
`VpcPeering` model — the platform derives them. Do not send them on create.

## 3. Approval body — `PUT /v1/vpc-peerings/{id}/approval` (model `VpcPeeringApprovalRequest`)
| field | req | type |
|---|---|---|
| `type` | **REQ** | enum `(CREATE_APPROVE, CREATE_CANCEL, CREATE_REJECT, CREATE_RE_REQUEST, DELETE_APPROVE, DELETE_CANCEL, DELETE_REJECT)` |

## 4. Routing rule — `POST /v1/vpc-peerings/{id}/routing-rules` (model `VpcPeeringRuleCreateRequest`)
| field | req | type |
|---|---|---|
| `destination_cidr` | **REQ** | string |
| `destination_vpc_type` | **REQ** | enum `(REQUESTER_VPC, APPROVER_VPC)` |
| `tags` | opt | array[Tag] |

## 5. State machine
`VpcPeering.state` enum: `CREATING, CREATING_REQUESTING, ACTIVE, REJECTED, CANCELED,
EDITING, DELETING, DELETING_REQUESTING, DELETED, ERROR`. `account_type` = `SAME` |
`DIFFERENT`.

## 6. The same-account-no-approval rule (CONFIRMED)
- When requester and approver VPCs are in the **same account** (`account_type=SAME`),
  the peering goes **straight to ACTIVE — no approval call is allowed**. Calling the
  approval endpoint returns platform `400 "Approval is not required for Same Account
  VPC peering"` (peering probe 27401023616).
- **Therefore `vpc_peering_approval` is UNTESTABLE in this single-tenant test account**
  — exercising approval needs a second account. Classify it BLOCKED-by-environment, not
  a provider defect.

## 7. CONTRADICTION: provider vs API (issue #61)
- The **provider create still 400s** `"no value given for required property
  approver_vpc_name"` even on the patched build (run 27736779212). The provider's
  `vpcpeering.go:207-220` tries to auto-resolve `approver_vpc_name` from
  `approver_vpc_id` but does not populate the API request.
- **api_docs.json proves the create schema does NOT contain `approver_vpc_name`** — the
  only required ids are `requester_vpc_id`, `approver_vpc_id`, `approver_vpc_account_id`.
  The provider is inventing a required field the platform never asked for. The real
  earlier root cause (peering probe 27401023616) was the provider sending
  `"description": null` (SDK `NullableString`), fixed in `vpcv1/vpc.go`; the
  `approver_vpc_name` issue is a **separate, still-open provider bug** — the fixture is
  correct, the provider must stop requiring/sending that field.
