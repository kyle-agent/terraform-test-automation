# v4.0.0 reconciliation — what upstream still needs from our fork

**Baseline:** upstream **v4.0.0** (`SamsungSDSCloud/terraform-provider-samsungcloudplatformv2`,
commit `bc2a1a6`, "Update Provider v4.0.0"). Tested via the **released binary** from GitHub
Releases (`SCP_PROVIDER_SOURCE_BUILD=0`, `SCP_PROVIDER_VERSION=4.0.0`) — the v4 SDK
(`terraform-sdk-samsungcloudplatformv2/v4`) is a private module, so v4 cannot be built from
source in our tokenless CI; the published binary IS the fresh-upstream artifact.

**Our fork:** v3.3.x-era base (`6beee9b`) + ~17 behaviour fixes on branch
`claude/epic-ride-9zotgp`. Backup of the patched main kept as `main-v3-snapshot`; v4.0.0
checked out as branch `v4-baseline` for the comparison.

**Method:** (1) **code-delta** — read v4.0.0 source and compare each of our fixes against
v4's version of the same file/function (build-independent, conclusive: if v4's source still
contains the defective path, v4 lacks the fix); (2) **empirical** — run the full capability
sweep against the released v4.0.0 binary (see "Empirical results" below).

## Headline

**v4.0.0 adopted almost none of the reported fixes.** Of ~60 open issues, only **4** are
resolved in v4; the rest (including all but one of our behaviour fixes) still carry the
original defect in v4 source. The fixes below are ready to forward to the provider team —
each cites the exact unfixed v4 location plus our proven patch.

---

## A0. v4 improvements BEYOND our tracked issues (found via the 6beee9b→v4.0.0 diff)

v4.0.0 ships as a single squashed commit (no CHANGELOG / granular history), so these were
found by diffing the source (849 files, +25k/-17k). The standout is import support:

- **`ImportState` added to 37 resources across 17 families** (we had 1): backup, baremetal,
  baremetalblockstorage, budget, certificatemanager, configinspection, directconnect, dns,
  filestorage, firewall, iam, loggingaudit, multinodegpucluster, plannedcompute,
  resourcemanager, ske, virtualserver. **This directly supersedes our #81 framing** ("no
  ImportState on ANY resource") — though `vpc_vpc` (the resource named in #81) still lacks it.
  Our dashboard marks `import` as `unsupported` almost everywhere; on v4 these 37 now import.
- **~13 new plan-time validators** that prevent the opaque-400 class: dns record `type`
  (`A/AAAA/CNAME/MX/TXT/SPF`), firewall `direction` (`ingress/egress`), LB method
  (`ROUND_ROBIN/RATIO`), `ENABLE/DISABLE`, `PUBLIC/PRIVATE`, `ICMP/TCP/HTTP/HTTPS`, a
  `^[a-zA-Z0-9-]*$` name regex, etc. (partial overlap with #55/#86).
- Plus the 4 closed issues below (#59/#25/#71/#89).

Everything else is largely **unchanged** — the systemic gaps (#52 Read-404, #33 whitelist
Update, #62 raw types, #48 UseStateForUnknown, #49 immutable hard-error) persist in v4. Net:
v4's real behavioural improvements = **import axis + a few validators + 4 fixes**.

## A. Fixed in v4.0.0 → issues CLOSED

| issue | resource | what v4 fixed (evidence) |
|---|---|---|
| #59 | vpc_subnet | `client/vpcv1d2/subnet_model.go:47` `DnsNameservers types.Set`; `:93` null/unknown-safe convert; Read uses `types.SetValueFrom` — replan churn gone. |
| #25 | eventstreams/mysql cluster mappers | chained `.Get()` nil-deref now guarded (`service/eventstreams/cluster.go:478`, `service/mysql/cluster.go:475,526`). |
| #71 | ske_nodepool | Update branches version-upgrade (`UpgradeNodepool`) vs label/taint/scaling (`UpdateNodepoolLabels/Taints/LinkedResources/Nodepool`) — non-version changes no longer dropped. |
| #89 | loggingaudit_trail | v4 SDK adds `IamRoleId/LogGroupName/ServiceWatchYn` (`client/loggingaudit/loggingaudit.go:89-91,121-122`); **empirically green** on v4 (run 27724880374, novpc: validate→destroy + import all ok). Strict-decode orphan resolved. |

---

## B. STILL broken in v4.0.0 → re-apply our fix + guide the provider team

Each row: the defect still present in v4 (file:line), and our fork commit that fixes it.

| issue / area | v4 unfixed location | our fix |
|---|---|---|
| **#60** vpc_cidr | `service/vpc/vpc_cidr.go` Read body is `// TODO … RemoveResource`; Delete is `AddError("Delete Not Implemented")` | implement Read (`GetVpcWithStatus`, remove-on-404) + Delete (`RemoveVpcCidr` + poll-gone) — commit `a73f541`/`d883fab` |
| **#61** vpc_vpc_peering | `client/vpcv1/vpc.go:79` CreateVpcPeering sends `Description: *NewNullableString(...)` unconditionally; Create body omits `ApproverVpcName` (it exists only in the **Computed** nested block, not as input) | omit unset description; expose+forward `approver_vpc_name` as an input — commit `11467ad`/`d883fab`/`a73f541` |
| **vpc_publicip** v1.2 read | `service/vpc/publicip.go` Read still calls v1.1 `GetPublicip`; no `GetPublicipWithStatus`/v1.2 SUBNET enum | read via v1.2 so SUBNET-attached IPs decode + remove-on-404 — commit `d883fab` |
| **vpc_subnet_vip_nat_ip** destroy | `service/vpc/subnet_vip_nat_ip.go` Delete waits only for the NAT IP `DELETED`; no publicip-detach wait (root cause = v1.1 publicip read above) | wait for publicip detach (v1.2) before returning — commit `d883fab` |
| **#76** TGW + private_nat waiter hang | every waiter called with **empty `[]string{}` Pending**: `transit_gateway.go:196,319`, `transitgateway_vpcconnection.go:178,263`, `vpc_transit_gateway_rule.go:238,316`, `transit_gateway_firewall_connection.go:206,304`, **`private_nat.go:226,378`** | pass real transitional Pending states so terminal ERROR short-circuits instead of hanging the full timeout — commit `e3bf606` (extend to `private_nat.go`, which our original missed) |
| **#77** loadbalancer waits | `service/loadbalancer/loadbalancer.go:247` Create ends with no status poll; Delete (`:344`) no wait | wait-for-ACTIVE on Create + wait-until-gone on Delete — commit `3defab1`/`fbdeed2`. **Adapt:** v4 `WaitForStatus` (common.go:53) signature changed (adds `timeout,delay,minTimeout,maxConsecutiveErrors`). |
| **#85** lb_member | `service/loadbalancer/lbmember.go:261,280` required-check has no `IsUnknown()` guard; Delete (`:475`) no parent-EDITING wait | defer the required-check when value `IsUnknown()`; wait for server-group to leave EDITING on Delete — commit `e3bf606`/`d883fab` |
| **#58** iam_access_key | `client/iam/iam.go` has no `DisableAccessKey`; `service/iam/accesskey.go:396` Delete calls `DeleteAccessKey` directly | disable an ENABLED key before delete — commit `a73f541` |
| **#75** iam_role | `client/iam/iam.go:599` CreateRole uses `var policyIds []string` (nil → JSON `null`) | `policyIds := []string{}` so empty serializes as `[]` — commit `e3bf606` |
| **#67** virtualserver_server | `service/virtualserver/server.go:290` State has no `Default:`; create guard `:1614` lacks `!IsUnknown()` | `stringdefault.StaticString("ACTIVE")` + unknown-guard — commit `e3bf606` |
| **#78** billing planned_compute | `service/plannedcompute/plannedcompute.go:72` ContractType has no `Validators` | `stringvalidator.OneOf("01","03","05")` — commit `8c26bd8` |
| **#80** backup (shared helper) | `client/common.go:142` `for _, d := range detail.([]interface{}) { details = append(details, d.(string)) }` — unchecked assertion panics on a non-string element of a 500 body | comma-ok + skip non-strings (benefits ALL callers) — commit `8c26bd8` |
| **#56** servicewatch_alert | `service/servicewatch/alert.go:539` `return [][]string{keys}` with nil `keys` → `[[]]` | `if len(keys)==0 { return [][]string{}, nil }` — commit `8c26bd8` |
| **#54** cloudmonitoring event_policy | `client/cloudmonitoring/model.go:130` `NotificationRecipient []NotificationRecipient`; `service/cloudmonitoring/event_policy.go:324` ListNestedAttribute has no NestedObject; `:537` `nil` | model→`types.List`, full NestedObject, AttributeTypes, `ListNull` — commit `8c26bd8`. *(cloudmonitoring is deprecation-flagged on our side; confirm v4 still ships it before porting.)* |
| **filestorage_replication** Delete | `service/filestorage/replication.go:342` Delete deletes directly; no pause→wait-paused→delete→wait-gone | full Delete sequence + `PauseVolumeReplication`/`waitForReplicationGone` — commit `645d620` |
| **filestorage / loggingaudit** omit-null | `client/filestorage/filestorage.go:176,182` and `client/loggingaudit/loggingaudit.go:73-91` attach optionals as explicit JSON `null` unconditionally (v4 even adds 3 MORE such fields) | attach optionals only when configured (`IsNull/IsUnknown` / `setIf`) — commit `ab4dbbe` |

### Also still-broken (reported, not previously patched by us)
- **#81** vpc_vpc — no `ImportState` (v4 added ImportState to 37 resources but **not** vpc_vpc).
- **#79 / #93** dns_private_dns — Delete calls `DeletePrivateDns` directly, no unbind/wait → destroy leak.
- **#92** Update "Value Conversion Error" — raw Go types on Update (e.g. vpc_port `[]string SecurityGroups`); v4 unchanged.
- **#62** systemic raw Go types (`[]string`, int32) in models. **#52** Read 404 → `RemoveResource` missing on ~75/83 resources. **#48** computed nested objects lack `UseStateForUnknown()`. **#49** immutable attrs hard-error instead of `RequiresReplace()`. **#33** Update field-whitelists silently drop changes. **#69** no divisible-by-8 size validator. **#88** filestorage_replication delete. **#86** image url/os_distro validators. **#74** iam_user account_id still Optional. **#70** ske_nodepool k8s-version validator. **#27** lb_member state saved before wait. **#26** unchecked type assertion in `GetStatusCodeFromError`. (full list in the audit.)

---

## C. UNCLEAR — SDK-side (cannot verify from the provider repo)

These live in the **private v4 SDK** (`terraform-sdk-samsungcloudplatformv2/v4`), not in the
provider source we can read:
- **filestorage 1.1 tolerant-400 decode** — our fork patched the vendored SDK; v4 uses its own SDK.
- **loggingaudit `Trail1dot1` response strict-decode** — the create-request fields are present in v4, but the response-model `DisallowUnknownFields` behaviour is SDK-internal. (Empirical `loggingaudit_trail` green on v4 would confirm it's resolved → also closes #89.)

## D. PLATFORM / DOCS-ONLY (not provider-fixable by us)
- **#82** budget_budget / dns_public_domain_name / certificate_manager — server-side **500** on create.
- **#83** DBaaS weak validation — partially addressed (v4 adds some OneOf), most constraints still unenforced.
- **#42–#47, #53, #64/#65/#66** — docs / examples / server-type catalog data source — feature requests, no behaviour fix.

---

## Empirical results (released v4.0.0 full sweep)

_Run `27724880374` (SELECT_STATUS=green,broken,untested on the v4.0.0 binary). Results
appended on completion — used to (a) confirm #89 (loggingaudit_trail), (b) catch any v4
schema-breaking changes that invalidate our v3-era fixtures vs genuine v4 defects, and
(c) reveal v4's new resources (searchengine_cluster, sqlserver_cluster, ske_nodepool)._

| scenario | our patched | v4.0.0 | interpretation |
|---|---|---|---|
| _(to be filled from the v4 sweep matrices)_ | | | |

---

## Recommended actions for the provider team

1. **Re-apply Section B fixes onto v4** (most port verbatim; #77/#85 need the new
   `WaitForStatus` signature; #76 must also cover `private_nat.go`).
2. **Systemic items (#62/#52/#48/#49/#33)** are worth a single sweep across families rather
   than per-resource patches.
3. **Add `ImportState`** to the remaining resources (#81) — v4 already did 37, finish the set.
4. SDK-side (#88 decode tolerance, loggingaudit response model) must be fixed in the
   private v4 SDK repo.
