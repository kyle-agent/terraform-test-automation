# v4.0.0 우선 수정 요청 (P0) — 개발팀 전달용

`terraform-provider-samsungcloudplatformv2` **v4.0.0**(released, `bc2a1a6`) 기준, 우리가
블랙박스 terraform 커버리지로 확인한 **필수(P0) 결함 12건**입니다. 기준은 "이게 없으면
리소스를 **생성할 수 없거나**, destroy 시 **리소스가 누수되거나**, 프로바이더가 **멈춤/패닉**"
입니다. 각 항목은 **문제 → 현재 v4 소스(파일:라인) → 수정안 → 검증**으로 정리했습니다.

> 라벨: 이 12건은 fork 이슈에 `v4-must-fix`. 전체 미반영(45건)은 `v4-still-lacks`,
> 패치 검증분(7건)은 `fix-verified-green`. 코드 위치는 v4.0.0 소스 기준입니다.

---

## A. 생성 자체가 막힘 (리소스 사용 불가)

### #67 — `virtualserver_server`: `state` 미지정 시 create 항상 실패
**문제.** `state`(Optional+Computed)를 설정하지 않으면 — 즉 문서의 기본 사용법 — apply가
`Invalid server state. Server state must be 'ACTIVE' during creation.` 로 실패합니다. 컴퓨트
티어 전체가 사실상 생성 불가. (값을 미지정하면 plan 단계에서 `unknown`인데, 가드가 이를
`null`이 아닌 빈 문자열로 읽어 분기됨.)

**현재 v4 소스.** `samsungcloudplatform/service/virtualserver/server.go`
```go
// :290  State 스키마 — Default 없음
common.ToSnakeCase("State"): schema.StringAttribute{ Optional: true, Computed: true },

// :1614  create 가드 — IsUnknown 미검사
if !plan.State.IsNull() {
    if plan.State.ValueString() != "ACTIVE" {
        resp.Diagnostics.AddError("Error Creating Server",
            "Invalid server state. ... State: "+plan.State.ValueString())   // unknown -> "" -> 실패
        return
    }
}
```
**수정.** unknown을 가드에서 제외(명시적으로 비-ACTIVE를 준 경우만 거부):
```go
if !plan.State.IsNull() && !plan.State.IsUnknown() { ... }
```
그리고 `state` 속성에 `stringplanmodifier.UseStateForUnknown()` 추가(plan churn 방지).
**검증.** `state` 없는 최소 config로 apply → 서버 ACTIVE 생성, replan clean, destroy OK.

### #75 — `iam_role`: 문서 예시대로 create 시 `400 Input should be a valid list`
**문제.** 문서의 `assume_role_policy_document` 예시 형태로 만들면 apply에서
`400 ... Input should be a valid list`. 가장 기본적인 IAM role을 만들 수 없음.

**현재 v4 소스.** `samsungcloudplatform/client/iam/iam.go:599` (`CreateRole`)
```go
var policyIds []string        // nil 슬라이스 -> JSON "null"로 직렬화 (API는 [] 기대)
```
**수정.** 빈 컬렉션을 `null`이 아닌 `[]`로 보냄:
```go
policyIds := []string{}
// principals 등 다른 required 리스트도 동일 처리.
```
추가로, 400 에러에 어느 필드인지 surfacing(요청 바디 필드 경로 wrap).
**검증.** 문서 예시 config로 role 생성 → replan clean → destroy.

### #60 — `vpc_cidr`: Read/Delete 미구현 (refresh마다 증발 + destroy 에러)
**문제.** Read가 항상 state에서 리소스를 제거 → 매 refresh마다 리소스가 사라짐. Delete가
미구현 → destroy가 에러. (priority: critical)

**현재 v4 소스.** `samsungcloudplatform/service/vpc/vpc_cidr.go`
```go
// Read: 본문이 사실상 TODO + 무조건 RemoveResource
//   resp.State.RemoveResource(ctx)
// Delete: 미구현 에러
resp.Diagnostics.AddError("Delete Not Implemented", "...")
```
**수정.** 실제 Read(`GetVpcWithStatus`로 CIDR 존재 확인, 404면 remove-on-404)와
실제 Delete(`RemoveVpcCidr` 호출 후 사라질 때까지 poll) 구현.
**검증.** apply → 동일 plan은 no-op(증발 없음) → destroy로 CIDR 제거.

### #61 / #84.1 — `vpc_vpc_peering`: `approver_vpc_name` 미노출로 생성 불가
**문제.** API가 create에 `approver_vpc_name`을 요구하는데 입력 스키마에 없음 →
`no value given for required property approver_vpc_name`. 속성을 추가하면 `validate`에서
`Unsupported argument`. 즉 terraform으로 peering 생성 불가. (추가로 create가 `description`을
미설정 시에도 명시적 `null`로 보냄.)

**현재 v4 소스.** `samsungcloudplatform/client/vpcv1/vpc.go:79` (`CreateVpcPeering`)
```go
Description: *scpvpc.NewNullableString(request.Description.ValueStringPointer()), // 무조건 null
// VpcPeeringCreateRequest{...} 에 ApproverVpcName 자체가 없음.
// ApproverVpcName 은 읽기전용 Computed 중첩블록(model.go)에만 존재 — 입력 불가.
```
**수정.** `approver_vpc_name`을 **입력 속성**으로 노출하고 create 바디에 forward.
`description`은 설정된 경우에만 첨부(unset이면 생략).
**검증.** `approver_vpc_name` 지정 config로 peering 생성/삭제 성공.

---

## B. destroy 실패 → 리소스 누수 (비용/쿼터/보안)

### #77 — `loadbalancer`: create가 ACTIVE 대기 안 함 → destroy 실패 → 과금 LB 누수
**문제.** Create가 LB가 `CREATING`인 채로 반환 → 직후 destroy가
`The loadbalancer is not in a deletable state (state: CREATING)`로 실패 → **과금되는 LB가
누수**되고 이름도 점유됨.

**현재 v4 소스.** `samsungcloudplatform/service/loadbalancer/loadbalancer.go`
```go
// :247 Create — CreateLoadbalancer 후 상태 폴링 없이 바로 State.Set
// :344 Delete — DeleteLoadbalancer 직접 호출, deletable 대기 없음
```
(대조: `service/virtualserver/server.go`는 Create에서 ACTIVE까지 폴링함.)
**수정.** Create 후 `GetLoadbalancer`로 `ACTIVE`까지 폴링(ERROR 단락 + bounded timeout),
Delete는 전이상태(`CREATING/EDITING`)면 deletable까지 대기 후 삭제, 404는 성공 처리.
주의: v4의 `client.WaitForStatus`(common.go:53) 시그니처가 바뀜
(`timeout, delay, minTimeout, maxConsecutiveErrors` 추가) — wait 헬퍼에 인자 반영.
**검증.** LB apply 직후 destroy → 성공, 누수 LB 없음.

### #58 — `iam_access_key`: enabled 키 삭제 불가 → 살아있는 자격증명 누수 (보안)
**문제.** `is_enabled = true`로 만든 키는 destroy가
`Access key is Enabled.` 로 실패 → **활성 자격증명이 추적 불가 상태로 방치**(보안).

**현재 v4 소스.** `samsungcloudplatform/service/iam/accesskey.go:396` — Delete가
`r.client.DeleteAccessKey(...)`를 바로 호출(disable 단계 없음). `client/iam/iam.go`에
`DisableAccessKey`/disable 경로 없음(단, `UpdateAccessKey`는 존재).
**수정.** Delete에서 enabled면 먼저 비활성화 후 삭제(idempotent), 404는 성공:
```go
if state.IsEnabled.ValueBool() {
    state.IsEnabled = types.BoolValue(false)
    if _, err := r.client.UpdateAccessKey(ctx, id, state); err != nil { /* diag+return */ }
}
err := r.client.DeleteAccessKey(ctx, id)
```
**검증.** enabled 키 apply 후 destroy → 성공, 누수 자격증명 없음.

### #79 / #93 — `dns_private_dns`: destroy가 안 풀려 VPC에 붙은 채 → VPC 409 누수
**문제.** 부모 `dns_private_dns`(VPC에 `connected_vpc_ids`로 바인딩) + 자식
`dns_hosted_zone`/`dns_record` 구성에서 destroy가 부모를 제거하지 못함 → VPC 삭제 시
`409 Cannot terminate due to associated resources` → **dns_private_dns + VPC 누수**.
(apply/replan/update는 green, destroy만 실패.)

**현재 v4 소스.** `samsungcloudplatform/service/dns/...` — Delete가 `DeletePrivateDns`를
직접 호출하고 connected VPC unbind/비활성/완전삭제 대기가 없음.
**수정.** Delete가 connected VPC(들)에서 unbind + deactivate하고 리소스가 실제로 사라질
때까지 대기. 그래야 자식→부모 순 destroy + 후속 VPC 삭제가 409 없이 완료.
**검증.** private_dns + hosted_zone/record apply → destroy → VPC 삭제까지 409 없이 성공.

### #88 — `filestorage_replication`: destroy 직삭제 실패 → 풀 볼륨 점유 누수
**문제.** replication 정책이 활성인 채로 삭제 API를 직접 호출 →
`400 Cannot delete volume because replication is in use ... paused > delete`로 destroy 실패
→ orphan replication이 소스 풀 볼륨을 점유(누수).

**현재 v4 소스.** `samsungcloudplatform/service/filestorage/replication.go:342` — Delete가
pause/poll/wait 없이 `DeleteVolumeReplication`을 직접 호출. `PauseVolumeReplication`/
`waitForReplicationGone` 부재.
**수정.** 문서 시퀀스대로: 정책 일시정지 → paused까지 poll → 삭제 → 사라질 때까지 대기.
(추가로 400 바디 tolerant decode로 실제 API 메시지 노출.)
**검증.** replication apply → destroy → orphan 없음, 풀 볼륨 해제.

### #84.2 — `vpc_subnet_vip_nat_ip`: destroy 시 publicip read 실패 → 누수
**문제.** apply는 성공하나 destroy가 publicip read에서
`SUBNET is not a valid PublicipAttachedResourceType`로 실패 → publicip 누수.
(실증 run 27724880374에서 재현 — leaked `vpc_publicip`.)
**현재 v4 소스.** `service/vpc/subnet_vip_nat_ip.go` Delete는 NAT IP의 `DELETED`만 대기.
근본원인은 publicip read가 v1.1(이 enum에 SUBNET 없음)을 사용 — v4에 `GetPublicipWithStatus`/
v1.2 경로 없음.
**수정.** publicip read를 v1.2(SUBNET enum 포함)로, NAT 삭제 후 publicip detach까지 대기.
**검증.** subnet_vip_nat_ip apply → destroy → publicip까지 정리.
*(#84는 vpc_vpc_peering[= #61], vpc_endpoint "subnet not found"도 포함 — peering은 #61 참고.)*

---

## C. 자동화 멈춤 / 프로바이더 패닉

### #76 — VPC waiter: 빈 Pending + 120m → ERROR/parked 상태에서 2시간 행
**문제.** VPC 계열 status waiter가 모두 `Pending=[]`로 호출되고 `WaitForStatus` 타임아웃이
120분 → transit_gateway/private_nat 등이 `ERROR`/parked에 빠지면 ERROR 단락 없이 **2시간**
폴링 → apply/destroy 전체가 멈추고 자동화에선 teardown까지 막혀 누수 위험.

**현재 v4 소스.** `samsungcloudplatform/client/common.go` (`WaitForStatus`, `retry.StateChangeConf`,
120m) — 호출부가 `[]string{}` Pending 전달:
`transit_gateway.go:196,319`, `transitgateway_vpcconnection.go:178,263`,
`vpc_transit_gateway_rule.go:238,316`, `transit_gateway_firewall_connection.go:206,304`,
`private_nat.go:226,378`.
**수정.** (1) Pending에 실제 전이상태(`CREATING/EDITING` → ACTIVE, `DELETING` → DELETED)를
채워 예기치 않은 상태는 즉시 실패. (2) refresh에서 `ERROR` 상태 즉시 단락. (3) 네트워크
리소스는 120m 대신 15~20m 등 작업별 타임아웃.
**검증.** ERROR로 빠지는 TGW를 apply → 120m가 아닌 수 분 내 실패. DELETING 지연 destroy도 즉시 에러.

### #80 / #26 — 500/특정 에러 응답에서 프로바이더 패닉 (unchecked type assertion)
**문제.** 에러 디테일 파싱에서 검사 없는 타입 단언 → 500 응답의 `detail` 원소가 string이
아니면 **프로바이더가 패닉**(테스트/적용 프로세스가 크래시). v4 전체 스윕에서 fast-1/2/3
샤드가 이 패닉으로 산출물 없이 크래시함.
**현재 v4 소스.** `samsungcloudplatform/client/common.go:142` (`GetDetailFromError`)
```go
for _, d := range detail.([]interface{}) {
    details = append(details, d.(string))   // 비-string 원소면 panic
}
```
(`#26`은 `common/virtualserver/virtualserver.go`의 `err.(*scpsdk.GenericOpenAPIError)` 동류.)
**수정.** comma-ok로 안전하게, 비-string은 스킵(모든 호출자 이득):
```go
for _, d := range detail.([]interface{}) {
    if s, ok := d.(string); ok { details = append(details, s) }
}
// #26: if genericErr, ok := err.(*scpsdk.GenericOpenAPIError); ok { ... }
```
**검증.** 500/비정형 에러 바디에서 패닉 없이 클린 진단 반환.

---

## D. 관용적 사용 차단

### #85 — `loadbalancer_lb_member`: unknown `object_id` 거부 → 같은 apply의 서버 연결 불가
**문제.** `object_type="VM"`일 때 `object_id` 필수 검사가 **unknown(계산값)**을 "누락"으로
취급해 plan 실패 → 같은 apply에서 만든 server의 id(`known after apply`)를 member에 연결하는
표준 구성이 불가.
**현재 v4 소스.** `samsungcloudplatform/service/loadbalancer/lbmember.go:261,280` — 필수 검사가
`IsNull()/빈문자열`만 보고 `IsUnknown()` 미고려.
**수정.** plan 검증에서 값이 `IsUnknown()`이면 검사 스킵(known일 때만 enforce). LB 계열의
다른 "required-when-X" 검증도 동일.
**검증.** server + server_group + member를 한 apply로 생성 성공.

---

## 우선순위 요약

| 분류 | 이슈 | 한 줄 |
|---|---|---|
| 생성불가 | #67, #75, #60, #61 | server/iam_role/vpc_cidr/vpc_peering 생성 불가 |
| 누수 | #77, #58, #79, #88, #84 | LB/access-key/dns/replication/nat-ip destroy 누수 |
| 멈춤·패닉 | #76, #80(#26) | 2시간 행 / 프로바이더 패닉 |
| 차단 | #85 | 같은-apply LB member 구성 차단 |

각 이슈 본문에 재현 .tf와 실행 로그가 있습니다. 우리 fork(`claude/epic-ride-9zotgp`)에
#58/#67/#75/#76/#77/#85/#88은 **검증된 패치**(`fix-verified-green`)가 있어 그대로 참고 가능합니다.
