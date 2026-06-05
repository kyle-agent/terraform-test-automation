# SCP Terraform Provider 테스트 전략 (구조화 정리)

> 목적: `terraform-provider-samsungcloudplatformv2`의 리소스를 **full-lifecycle(생성→수정→파괴)**로
> 검증하고, provider/플랫폼 문제를 발견·이슈화하며, 테스트가 남긴 자원을 **누수 0(leak 0)**으로
> 정리한다. API는 *보조* 수단(terraform이 못 지우는 자원 정리, 필수 값 조회, 존재 확인)으로만 쓴다.
>
> 이 문서는 4개 축으로 분리한다: **① 테스트 전략 · ② 실행 · ③ 문제 분석 · ④ 클린업.**

---

## ① 테스트 전략 (What & How)

### 1.1 판정 모델
모든 (제외 대상이 아닌) 리소스는 최소 한 번 다음 중 하나로 판정한다.
- **GREEN** — `apply`(생성) + `destroy`(파괴)가 깨끗이 성공.
- **RED** — plan/apply/destroy 중 재현되는 실패. provider/플랫폼 이슈로 분리.
- **BLOCKED** — 계정 권한·쿼터·플랫폼 제약 등 외부 요인으로 판정 불가.

대시보드(`coverage/coverage.json` → GitHub Pages)에 stage별(validate/plan/apply/update/replan/destroy/import) 기록.

### 1.2 하네스
- Go capability-matrix 테스트: `tests/capability/matrix_test.go`.
- 환경 게이트: `CAPABILITY_MATRIX=1`, `MATRIX_SCENARIOS=<쉼표목록>`, `MATRIX_PARALLEL=N`(시나리오 동시 실행).
- 시나리오 = `scenarios/<name>/main.tf` (리소스별 최소 fixture).

### 1.3 VPC-pool 병렬 아키텍처 (핵심)
계정 **VPC 쿼터가 5개**라서 동시 VPC 수를 제어하는 것이 전체 전략의 축이다. 3개 레인으로 분리:

| 레인 | VPC 사용 | 내용 |
|---|---|---|
| **novpc** | 0개 | VPC 비의존 제품(iam/dns/cert/billing/servicewatch/resourcemanager) — 부트스트랩 없이 고병렬(MATRIX_PARALLEL 6) |
| **pool** | 샤드당 1개 | VPC 의존 제품. 각 matrix 샤드가 VPC 1개를 부트스트랩 → 그 안에서 시나리오 실행 → 항상 teardown. `max-parallel`로 동시 VPC 수 제한 |
| **selfvpc** | 자체 생성 | 스스로 VPC를 만드는 시나리오(vpn/igw/endpoint/peering). `needs: pool`로 pool VPC 회수 후 실행 → 쿼터 충돌 방지 |

- pool 샤드 구성: **vpc1**(네트워크: port/nat/sg/firewall/subnet/cidr/vip), **vpc2**(컴퓨트/스토리지: server/volume/filestorage/backup/gslb), **DBaaS 엔진별 단일 샤드**(엔진당 ~30분이라 1샤드=1엔진으로 분리, 타임아웃·누수 방지).
- `max-parallel`: 안전하게 **2** (leftover VPC 등 여유분 고려). 깨끗한 쿼터에선 3까지 가능.

### 1.4 제외(스코프 밖)
- 가족 단위 제외: baremetal, cloud monitoring, configinspection, vertica.
- provider 차단으로 제외/우회: TGW(#76 hang), LB(#77 leak), private-dns destroy(#79).

---

## ② 실행 (Execution) — 워크플로

| 워크플로 | 트리거 | 역할 |
|---|---|---|
| `.github/workflows/coverage-sweep-pool.yml` | push(자기 파일) / dispatch | 메인 커버리지 sweep (novpc + pool + selfvpc) |
| `.github/workflows/dbaas-probe.yml` | push(`cmd/dbaas_probe/**`) / dispatch | DBaaS 값 확인 probe + 누수 정리(기본 `cleanup`) |
| `.github/workflows/api-reaper.yml` | push(`cmd/api_reaper/**`) / dispatch | 계정 전체 test-자원 sweep (HMAC API) |

- 환경: `environment: scp-integration`. 자격증명은 `secrets.SCP_TF_ACCESS_KEY/SECRET_KEY`,
  설정값은 `vars.SCP_TF_AUTH_URL / SCP_DEFAULT_REGION / SCP_ACCOUNT_ID` (이 3개는 **secret이 아니라 variable**).
- dispatch는 MCP 토큰으로 403 → **push가 실제 트리거 수단**. (워크플로 파일/스크립트에 한 줄 주석을 더해 push로 발사)
- 타임아웃: DBaaS 샤드는 생성(ACTIVE 대기 ~15-20분)+파괴(~10-15분)라 go test `-timeout 60m`, job `timeout-minutes 75`.

### 실행 순서(권장 루틴)
1. (필요시) `api-reaper` 1회 → 쿼터/누수 초기화.
2. `coverage-sweep-pool` push → 전체 sweep.
3. 실패 샤드는 로그로 원인 분리(아래 ③) → fixture 수정 또는 이슈화.
4. 종료 후 `api-reaper`로 leak 0 확인.

---

## ③ 문제 분석 (Problem Analysis)

### 3.1 발견·등록한 provider 이슈
- **#58 / #60** — vpc_cidr replan 등.
- **#76** — VPC/TGW status-waiter hang (전이 상태 무한 대기).
- **#77** — LB create no-wait → destroy leak.
- **#79** — private-dns destroy 409.
- **#81** — **어떤 리소스도 `ImportState` 미구현** → terraform으로 누수 자원 입양·삭제 불가 (클린업을 API로 해야 하는 근본 원인).
- **#82** — public-domain-name create가 500인데 자원은 남음(orphan), DELETE API 자체가 없음.
- **#83** — **DBaaS 클러스터 전반**: 약한 client-side 검증 + 불투명 `400 value_error`(필드명 없음). plan은 통과, apply만 실패.

### 3.2 DBaaS 값 확인 방법론 (재사용 가능)
- 근거자료: `api-test-automation/framework/api_bodies.json` = 엔진별 **검증된 create body** 원본.
- 도구: `cmd/dbaas_probe/probe.py` — canonical body를 Open API에 직접 POST하고 **raw 응답을 그대로 출력**.
  terraform이 숨기는 에러 detail이 드러난다. (생성되면 자동 삭제 → leak 0)
- 이 방법으로 드러난 숨은 제약(전부 terraform plan은 통과하던 것):
  1. `name`/`instance_name_prefix` **max_length**(예시 name≤9, prefix≤8).
  2. `init_config_option.database_name/user/password` **비어있으면 안 됨**.
  3. OS block_storage `size_gb` = **104**.
  4. `service_ip_address`는 subnet 내 **빈 IP**여야 함 — **생략하면 자동 할당**(우리 fixture가 채택).

### 3.3 CREATING-trap
DBaaS 클러스터는 생성 직후 **~15-20분간 삭제 불가**(`DELETE`→400), ACTIVE 후에야 삭제 가능(202).
→ provider create가 ACTIVE까지 기다리므로(소스 확인) terraform 경로는 destroy가 깨끗하지만,
API로 직접 만든 클러스터는 즉시 삭제가 안 됨(클린업 시 ACTIVE 대기 재시도 필요).

### 3.4 환경/계정 요인
- **VPC 쿼터(5)** — leftover VPC가 쿼터를 잡으면 부트스트랩이 `"number(5) of VPCs ... exceeded"`로 실패.
  → DBaaS 실패로 오인하기 쉬움(실제로 1차 pool 실패의 진짜 원인이었음). 클린업 후 동일 fixture가 전부 green.
- **계정 권한 BLOCKED** — iam_user(401), iam_user_policy_bindings(403), loggingaudit_trail(403).

### 3.5 현재 커버리지 스냅샷
- **DBaaS 5/8 GREEN**: mysql, postgresql, mariadb, epas, cachestore (terraform create+destroy 검증).
- **DBaaS 3/8 미해결**: sqlserver, searchengine, eventstreams — 각각 **필드명 없는 단일 `value_error`**.
  콘솔/문서의 정상 payload 필요(메일 문의 준비됨). eventstreams는 license/role이 아니라 토폴로지(`is_combined`/그룹 수) 의심.
- 대시보드: https://kyle-agent.github.io/terraform-test-automation/

---

## ④ 클린업 (Cleanup) — 누수 0 원칙

### 4.1 도구
- `cmd/api_reaper/sweep_all.py` — 계정 전체에서 **test prefix**(`regr/rpv/rps/rpkp/rpfs/rske/rlb/rtgw/igw_/fw_igw`) 자원을 **의존성 역순**으로 삭제. 완료 시 `"sweep_all done: N resource(s) deleted"`.
- `cmd/api_reaper/reap.py` — 특정 VPC/TGW를 id/name으로 정밀 삭제(라이브 자원 보호 위해 항상 타겟 한정).
- `cmd/dbaas_probe/probe.py cleanup` — probe가 누수시킨 DBaaS 클러스터를 id로 삭제(CREATING이면 ACTIVE 대기 후 삭제).
- `.claude/skills/scp-api/` — HMAC 단발 CLI(get/list/exists/delete) + 인증/호스트/순서 문서.

### 4.2 삭제 의존성 순서 (중요)
- **VPC**: 자식 먼저 — subnets/igw/publicips/ports/peerings/endpoints/subnet-vips/private-nats/tgw-connections → VPC(409 재시도).
- **TGW**: **routing-rules + uplink-rules → firewalls → vpc-connections → TGW** (규칙·연결 남으면 TGW 삭제 거부).
- **public-domain-name**: DELETE API 없음 → 콘솔/릴리스만.
- DBaaS delete는 비동기(202) → `wait_gone`으로 확인.

### 4.3 원칙
- 모든 pool 샤드는 `if: always()`로 teardown.
- 매 작업 종료 후 `api-reaper`로 **leak 0 재확인**.
- prefix/타겟 한정으로만 삭제(공유 계정의 라이브 자원 보호).

---

## ⑤ 보완 포인트 (사용자 검토 요청)

1. **DBaaS 3종 정상 payload** — 콘솔에서 만든 sqlserver/searchengine/eventstreams의 create 본문을 주시면 fixture에 즉시 반영·검증.
2. **계정 권한** — iam_user / iam_user_policy_bindings / loggingaudit_trail 의 401/403 (키 권한 부여 여부).
3. **VPC 쿼터 상향** 가능 여부 — 상향되면 pool `max-parallel`을 올려 sweep 시간 단축.
4. **dispatch 권한** — workflow_dispatch가 403이라 push로만 트리거 중. 정식 디스패치 토큰이 있으면 운영 편의↑.
5. 제외 가족(baremetal/monitoring/configinspection/vertica) 중 테스트 포함 원하는 항목 있으면 알려주기.

---

## ⑥ Best-practice 대조 및 개선안

> 참고: HashiCorp `terraform-plugin-testing`(acceptance tests/Sweepers/CheckDestroy/tfversion-checks),
> Terratest cleanup 가이드, Google/Azure terraform 테스트 가이드, `terraform test`(.tftest.hcl).
> **전제**: 우리는 third-party published provider를 라이브 클라우드에 **black-box e2e**로 검증한다
> (provider를 빌드/머지하지 않음). 따라서 "provider 레포 내 TF_ACC 테스트/Go Sweeper 작성"은 우리 lane이
> 아니며 → 대신 그 *패턴*을 우리 하네스에 이식하거나 provider 팀에 권고(#83)한다.

### 대조표
| Best practice | 표준 출처 | 현재 우리 상태 | 조치 |
|---|---|---|---|
| **CheckDestroy** = destroy 후 API로 실재 404 검증 | plugin-testing | terraform destroy 성공에만 의존, **API 재확인 없음** | **채택(高)** — destroy 후 `scp-api exists`로 404 확인. #77/#82류(‘destroy 성공인데 자원 잔존’) 자동 검출 |
| **Idempotency** = apply 후 재plan no-diff | testing-patterns | dashboard에 `replan` stage 칸은 있으나 미가동 | **채택(高)** — apply 후 `plan -detailed-exitcode`(2=perma-diff 버그) |
| **Sweepers**(leaked 자원 정리) | plugin-testing Sweepers | 동등 기능을 **Python reaper**로 자체 구현(prefix+의존성순서) | 유지. provider 팀엔 공식 Sweeper 추가 권고 |
| **Nightly 안전망 sweep**(cloud-nuke 패턴) | Terratest/Google | reaper는 **on-demand만** | **채택(高)** — `schedule: cron`으로 야간 sweep |
| **TTL/age 기반 정리**(N시간 초과만 삭제) | Terratest | prefix만 보고 삭제 → 공유계정 **동시 실행 레이스 위험** | **채택(中)** — created_at N시간 초과 자원만 |
| **Unique naming + tag**(TestRun 태그로 추적) | Terratest/Azure | suffix=run_id ✓, prefix ✓, **태그 없음** | **채택(中)** — 공통 태그(예 `created_by=regr`) 부여 → 태그 기반 sweep |
| **Static 선행 게이트**(fmt/validate/tflint) | Google/Spacelift | validate/plan은 있으나 fmt/tflint 미적용, 비싼 apply 선행 | **채택(中)** — fmt -check/validate/tflint를 **apply 전 fail-fast** |
| **테스트 피라미드**(plan/mock 빠른 층) | terraform test | 거의 **apply-only e2e** | 부분채택 — provider API 매핑 검증이 목적이라 e2e 유지하되, 회귀 빠른 확인용 plan층 보강 |
| **CheckDestroy/timeout 적정화** | plugin-testing | provider가 ACTIVE/삭제 대기(소스 확인), go test 60m/job 75m로 정렬 ✓ | 유지 |
| **격리(워크스페이스/state)** | 공통 | ephemeral runner + suffix로 분리 ✓ | 유지 |
| **provider 버전 매트릭스**(tfversion-checks) | plugin-testing | 단일 버전 핀 | 선택 — 릴리스 회귀 필요 시 |
| **`terraform test`(.tftest.hcl)로 통합** | terraform test | Go capability-matrix 사용 | 선택 — 자동 cleanup+HCL assert 이점 있으나 마이그레이션 비용. 현행 유지 |
| **CI 산출물**(JSON/JUnit/대시보드) | 공통 | capability-matrix.json + Pages 대시보드 ✓ | 유지(필요시 JUnit 추가) |

### 권장 우선순위 (낮은 노력·높은 효과 순)
1. **destroy 후 API 존재검증(CheckDestroy 등가)** — 가장 가치 큼. ‘조용한 누수’ 버그를 정량 검출.
2. **idempotency 재plan(no-diff)** — perma-diff 버그를 무료로 잡음. dashboard `replan` 칸 가동.
3. **야간 schedule sweep** — 안전망. cron 한 줄.
4. **fmt/validate/tflint 선행 게이트** — 비싼 apply 낭비 감소.
5. **TTL/태그 기반 sweep** — 공유계정 동시실행 레이스 방지(중요해질 수 있음).

### 의도적으로 채택 안 함 (이유 명시)
- **provider 레포 내 TF_ACC 어셉턴스 테스트/Go Sweeper 직접 작성** — third-party provider를 소유/머지하지 않음. 대신 black-box e2e + 이슈화. (provider 팀엔 권고)
- **mock 기반 terraform test** — 목적이 provider의 실제 API 매핑 검증이라 mock은 무의미. 실제 클라우드 e2e 유지.
