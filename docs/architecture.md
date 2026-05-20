# Architecture

## 목표

`terraform-provider-samsungcloudplatformv2`에 보고된 사용자 영향 결함이 회귀하지 않도록 자동으로 감지하고, 회귀 시 해당 sub-issue를 자동 재오픈한다.

## 설계 원칙

1. **이슈와 1:1 매핑**: 모든 테스트는 provider 리포의 sub-issue(예: `#11 (2-A)`)를 가리킨다. 회귀가 잡히면 어느 결함이 되살아났는지 즉시 식별 가능.
2. **두 가지 모드**:
   - `dry-run` (PR 게이트): 실 자원 생성 없이 schema/plan 레벨 회귀만 검증. 빠르고 안전.
   - `integration` (nightly): 실제 자원 생성·재실행·삭제까지 수행. 상태 일관성 및 부분 실패 시나리오 검증.
3. **테스트는 작고 자기서술적**: 픽스처와 헬퍼는 공유하되, 각 테스트는 하나의 결함만 검증한다.
4. **CI가 곧 리포트**: 통과/실패 결과가 JUnit + JSON으로 떨어지고, 실패는 즉시 provider 리포 sub-issue로 재오픈된다.

## 모듈

```
+--------------+      +----------------+      +-------------------+
|  scenarios/  | ---> |  tests/<chap>/ | ---> |  tests/common/    |
|  (.tf 픽스처) |      |  (Go 테스트)    |      |  (CLI 래퍼·진단)   |
+--------------+      +----------------+      +-------------------+
                                |
                                v
                      +-------------------+
                      |  out/results.json |
                      +-------------------+
                                |
                +---------------+----------------+
                v                                v
       +------------------+           +-----------------------+
       |  out/junit.xml   |           |  scripts/publish_     |
       |  (CI summary)    |           |  report.sh → GH issue |
       +------------------+           +-----------------------+
```

## 데이터 흐름

1. `make test` → `go test ./tests/...`
2. 각 테스트가 `common.MustInit / Plan / Apply / Destroy` 호출
3. `common.Wrap()` 데코레이터가 결과를 `out/results.json`에 누적 기록
4. CI가 `out/` 아티팩트를 업로드
5. 실패 시 `scripts/publish_report.sh`가 results.json을 파싱해 해당 sub-issue 코멘트 + 재오픈

## 추가/제외 정책

- **추가 기준**: provider 측에서 fix PR이 머지되었거나 곧 머지될 결함이면 즉시 회귀 테스트 추가.
- **제외 기준**: docs only / 코드 변경 없음(예: README, CONTRIBUTING)은 회귀 대상 아님.
- **dry-run 한계**: 부분 실패 시 orphan 검증, ACTIVE wait 회귀 등은 integration 필수.

## 확장 포인트

- `scenarios/`는 모듈화하여 동일 기반(`base_vpc`)을 재사용
- `common.Plan()`는 `terraform show -json` 기반 → 새 assertion 추가 용이
- 보안: integration 모드 secrets는 GitHub Actions Environment(`scp-integration`)로 격리, 코드와 분리
