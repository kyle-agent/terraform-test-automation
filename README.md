# terraform-provider-samsungcloudplatformv2 회귀 테스트 자동화

`terraform-provider-samsungcloudplatformv2`에 보고된 사용자 영향 결함이 회귀하지 않도록 검증하는 자동 회귀 테스트 시스템.

각 테스트는 보고 이슈(Chapter 1~7 + Deep Audit)와 1:1 또는 1:다로 매핑되며, 픽스가 머지된 뒤에도 회귀가 발생하면 자동으로 GitHub 이슈를 다시 열도록 설계되어 있다.

> **이 프로젝트는 멀티 에이전트로 운영됩니다.** 미션(2축: provider 검증 / 커버리지·회귀),
> 에이전트 구성, 세션 부트스트랩은 **[`AGENTS.md`](AGENTS.md)** 를 먼저 읽으세요.
> SCP 도메인 지식은 [`docs/domain/`](docs/domain/) + [`coverage/domain.yaml`](coverage/domain.yaml).

---

## 구성요소

| 구성 | 역할 |
|---|---|
| `tests/` | Go 기반 회귀 테스트 (chapter별 디렉터리) |
| `scenarios/` | 각 테스트가 사용하는 `.tf` 픽스처 |
| `tests/common/` | 공통 helper (Terraform CLI 래퍼, 진단 파서, 리포터, 동적 발견) |
| `tests/coverage/` | provider 리소스 표면 대비 시나리오 커버리지 회귀 가드 |
| `.github/workflows/` | 정기/PR 트리거 CI + **동적 회귀 파이프라인** |
| `scripts/` | 로컬·CI에서 쓰는 실행 스크립트 (발견·취합·반복 루프) |
| `config/` | 환경별 정책(드라이런/통합 모드, 리전 등) + provider 리소스 카탈로그 |
| `docs/` | 아키텍처 · 테스트 카탈로그 · 동적 워크플로우 · 새 테스트 추가 가이드 |

> SCP provider(`SamsungSDSCloud/samsungcloudplatformv2`, 현재 87개 리소스)를 **동적으로 발견·팬아웃·반복 실행**하는
> 파이프라인은 `docs/dynamic-workflow.md` 참고. 핵심: 챕터/시나리오/리소스를 워크플로우 수정 없이 자동 추적.
> 현재 87/87 리소스가 최소 dry-run 스키마 가드 시나리오를 가진다(`make coverage`). 시나리오는
> `scripts/gen_scenarios.py` 로 스키마에서 생성·실검증하며, 손으로 작성한 integration 시나리오로 점진 승격한다.

---

## 실행 모드

| 모드 | 환경변수 | 설명 |
|---|---|---|
| **dry-run** (기본, 안전) | `MODE=dry-run` | `terraform plan` 만 실행. 실제 자원 생성 없음. 스키마 결함·플랜 회귀만 검증. |
| **integration** | `MODE=integration` | `terraform apply` 까지 실제 실행. SCP 계정 자격증명 필요. 자원 생성·재실행·정리. |
| **canary** | `MODE=canary` | integration 중 최소 자원으로 빠르게 (옵션) |

자격증명 (integration 모드):

```bash
export SCP_TF_ACCESS_KEY=...
export SCP_TF_SECRET_KEY=...
export SCP_TF_AUTH_URL=https://iam.s.samsungsdscloud.com/v1
export SCP_TF_DEFAULT_REGION=kr-west1      # provider가 읽는 공식 이름
export SCP_DEFAULT_REGION=kr-west1         # 구 관례 alias (동일 값 유지)
export SCP_ACCOUNT_ID=...
```

---

## 빠른 시작

```bash
# 1) 도구 준비 (Go 1.22+, terraform 1.6+, jq 필요)
make tools

# 2) dry-run 전체 회귀
make test

# 3) 특정 챕터만
make test-chapter CH=chapter1_core

# 4) 단일 테스트
make test-one TEST=TestIssue02_SecurityGroupRule_IdReplace_Regression

# 5) integration 모드 (실 자원 생성)
MODE=integration make test

# 6) 동적 발견 — 무엇이 테스트되는지 확인
make discover

# 7) 리소스 커버리지 (provider 87개 리소스 대비)
make coverage

# 8) 반복 회귀 (flaky ↔ 회귀 분류)
make loop ITER=5
```

---

## 테스트 카탈로그 (요약)

자세한 목록은 `docs/test-catalog.md` 참고.

| Chapter | 테스트 ID | 검증 대상 |
|---|---|---|
| 1 | `TestIssue02_SecurityGroupRule_IdReplace_Regression` | id RequiresReplace 회귀 |
| 1 | `TestIssue03_DB_Update_HandlerMissing_Diff` | DB Update 핸들러 누락 diff |
| 1 | `TestIssue04_SKE_AdvancedSettings_RequiredOnRerun` | SKE nodepool 재실행 실패 |
| 1 | `TestIssue05_SecurityGroupRule_Panic_OnUpdate` | panic("implement me") 회귀 |
| 1 | `TestIssue06_ImportState_Coverage` | ImportState 미지원 |
| 2 | `TestIssue07_RequiredDefaults_DBPort` | DB Port Required 회귀 |
| 2 | `TestIssue08_LbListener_UpdateNoActiveWait` | 라우팅 부분 실패 |
| 2 | `TestIssue08D_LbListener_InsertClientIp_IsSetMisuse` | bool 변환 오류 |
| 2 | `TestIssue10_LbListener_Protocol_104` | 프로토콜 검증 오류 |
| 3 | `TestIssue11_Configure_HttpTimeout_CommentedOut` | client.go:234 |
| 3 | `TestIssue12_ServiceCheck_StallOnSlowEndpoint` | 헬스체크 stall |
| 3 | `TestIssue13_GetEndpointList_NoRetry` | IAM 재시도 |
| 4 | `TestIssue14_EventStreams_AllowableIpList_OrderDiff` | List 순서 diff |
| 4 | `TestIssue15_EventStreams_NestedList_Order` | nested list 순서 |
| 4 | `TestIssue16_EventStreams_PartialCreate_Orphan` | Create 부분 실패 orphan |
| 5 | `TestIssue17_FileStorage_ExternalRule_Deleted` | K8s Auto Scaling 호환 |
| 6 | `TestIssue19_Backend_Keyless_Documented` | 가이드 존재 검증 |
| Deep | `TestD01_SliceIndex_Panic_Multi` | 빈 리스트 인덱싱 |
| Deep | `TestD03_LbMember_StateBeforeWait` | wait 전 state.Set |
| Deep | `TestD09_NotFound_StringMatching` | 404 문자열 매칭 |
| ... | ... | ... |

---

## 결과 리포팅

테스트 종료 시:

1. JUnit XML → `out/junit.xml` (CI에 노출)
2. JSON 결과 → `out/results.json` (커스텀 리포터 입력; 멱등성 단언 실패 시 무엇이 diff났는지 `details`에 기록)
3. 챕터별 샤드 결과는 `scripts/merge_results.sh` 가 하나로 취합 + Markdown 요약(`$GITHUB_STEP_SUMMARY`)
4. **회귀 발견 시**: `scripts/publish_report.sh` 가 provider 리포(`terraform-provider-samsungcloudplatformv2`)의 매핑된 sub-issue를 자동 재오픈 (`GH_TOKEN` 필요)

---

## CI 트리거

- **PR / main push**: dry-run 전체 실행. 회귀 발견 시 check fail. (`regression.yml`)
- **Nightly Integration** (`nightly.yml`): **6시간마다**(`0 */6 * * *`) integration 모드 전체 실행.
  `scp-integration` 환경 시크릿 사용, 회귀 시 provider sub-issue 재오픈.
- **Dynamic Regression** (`dynamic-regression.yml`): **6시간마다**(3h offset) 챕터를 동적 matrix로
  팬아웃, `iterations`회 반복, 결과 취합. `workflow_dispatch` 입력으로
  `mode` / `iterations` / `chapter` / `coverage_min` 지정 가능.

> 정기 실행은 cron이 자동 처리하므로 버튼을 누를 필요가 없다. `workflow_dispatch` 는 즉시 한 번
> 돌리고 싶을 때만 사용. CI 러너에서 `registry.terraform.io` 가 막혀 있어도
> `scripts/setup_provider_mirror.sh` 가 provider를 GitHub releases에서 받아 mirror로 구성하므로
> `terraform init` 이 성공한다.

자세한 내용은 `docs/dynamic-workflow.md`.

---

## 새 테스트 추가

`docs/adding-tests.md` 참고. 요지:

1. `scenarios/<scenario_name>/` 에 `.tf` 픽스처 작성
2. `tests/<chapter>/issueNN_..._test.go` 에 테스트 함수 작성
3. `tests/common/` helper 활용 (`Plan`, `Apply`, `AssertNoChanges`, `AssertReplacementCount`, `AssertNoPanic` 등)
4. `docs/test-catalog.md` 에 한 줄 추가
5. PR 생성 → CI green 확인 → 머지

---

## 라이선스

내부 사용. 외부 공개 전 검토 필요.
