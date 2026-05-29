# Dynamic Regression Workflow

기존 회귀 스위트(`tests/`, `scenarios/`) 위에 올라가는 **동적·자가발견(self-discovering) 회귀 파이프라인**.

목표: SCP terraform provider(`SamsungSDSCloud/samsungcloudplatformv2`, 현재 87개 리소스)를 대상으로

1. 무엇을 테스트할지 **동적으로 발견**하고,
2. 챕터 단위로 **팬아웃(fan-out)** 해서 병렬 실행하고,
3. **반복(iterative)** 실행으로 flaky/회귀를 구분하고,
4. 결과를 **취합(fan-in)** 해 문제를 리포트하고 회귀 이슈를 재오픈한다.

이 파이프라인은 워크플로우 파일을 손대지 않아도 새 챕터/시나리오/리소스를 자동으로 따라간다.

---

## 구성요소

| 구성 | 역할 |
|---|---|
| `config/scp_resources.json` | provider의 실제 리소스 표면(registry 동기화본). "무엇을 테스트해야 하는가"의 소스 오브 트루스 |
| `tests/common/discovery.go` | 런타임 발견 primitive: repo root, 시나리오 스캔, 카탈로그 로드, 커버리지 계산 |
| `tests/coverage/coverage_test.go` | 커버리지 회귀 가드 (terraform/자격증명 불필요, 모든 모드에서 실행) |
| `scripts/discover.sh` | 챕터/시나리오를 GitHub Actions **동적 matrix** JSON으로 방출 |
| `scripts/merge_results.sh` | 샤드별 결과를 하나로 취합(fan-in) + JUnit + Markdown 요약 |
| `scripts/regression_loop.sh` | 반복 실행 + flaky↔회귀 분류 |
| `.github/workflows/dynamic-regression.yml` | discover → regression(matrix) → aggregate 워크플로우 |

---

## 동적 발견 (Dynamic discovery)

`scripts/discover.sh` 가 매 실행마다 `tests/*` 패키지와 `scenarios/*` 디렉터리를 스캔한다.

```bash
scripts/discover.sh list        # 사람이 읽는 요약
scripts/discover.sh chapters    # {"include":[{"chapter":...,"package":...,"tests":N}, ...]}
scripts/discover.sh scenarios   # {"include":[{"scenario":...,"dir":...}, ...]}
```

`tests/<새 챕터>/` 패키지나 `scenarios/<새 시나리오>/` 를 추가하면 다음 실행에서 자동으로 matrix에 포함된다 — 워크플로우 수정 불필요.

---

## 동적 CI 워크플로우

`.github/workflows/dynamic-regression.yml` 는 세 단계다.

```
discover  ── scripts/discover.sh 로 matrix 생성
   │
   ▼
regression ── chapter 당 1개 job (matrix 팬아웃), 각 job 안에서 ITERATIONS회 반복
   │           OUTPUT_DIR=out/<chapter> 로 격리 → 병렬 리포터가 서로 덮어쓰지 않음
   ▼
aggregate ── 모든 샤드 artifact 다운로드 → merge_results.sh 로 취합
             → Step Summary 출력 → 실패 시 publish_report.sh 로 이슈 재오픈
```

`workflow_dispatch` 입력:

| 입력 | 의미 |
|---|---|
| `mode` | `dry-run`(기본) / `integration` / `canary` |
| `iterations` | 각 챕터를 N회 반복 (flaky/회귀 흔들어 보기) |
| `chapter` | 특정 챕터만 (빈 값 = 동적 발견된 전체) |
| `coverage_min` | 리소스 커버리지가 이 % 미만이면 실패 (빈 값 = 리포트만) |

스케줄: 03:00 KST (기존 nightly integration 직후).

### 샤딩이 왜 중요한가

리포터(`tests/common/reporter.go`)는 `OUTPUT_DIR/results.json` 에 쓴다. 한 번의 `go test ./tests/...` 로 여러 패키지를 돌리면 패키지별 프로세스가 같은 파일을 덮어써 결과가 유실된다. 챕터별 팬아웃은 각 패키지에 **고유한 `OUTPUT_DIR`** 를 주고, `merge_results.sh` 가 마지막에 합치므로 이 문제가 사라진다. (로컬 `make test` 도 동일하게 챕터별로 샤딩한다.)

---

### validate 스윕의 환경 의존성

`terraform validate` 는 provider 설치(`terraform init`)가 필요하다. 네트워크 정책상
`registry.terraform.io` 가 막힌 환경(예: 403)에서는 provider를 받을 수 없어, validate 스윕은
**해당 시나리오를 fail이 아니라 skip 처리**한다(`common.Validate` 가 설치 실패를 감지). 따라서
잠긴 CI에서도 dry-run 게이트는 green을 유지하고, 레지스트리 접근이 가능하거나 provider mirror
(`TF_CLI_CONFIG_FILE`)가 설정된 환경에서는 실제 스키마 회귀를 잡는다.

의도적으로 불완전한 픽스처(필수 인자를 integration 변형에서 채우는 `import_smoke` 등)는 `.tf` 안에
`# regr:no-validate` 마커를 넣어 스윕에서 제외한다.

## 반복 회귀 (Iterative)

순서/타이밍 의존 회귀는 1회 실행으로는 놓치기 쉽다. `regression_loop.sh` 는 N회 반복하고 테스트별로 분류한다.

```bash
make loop ITER=5                 # 전체를 5회 반복
make loop ITER=5 LOOP_CH=coverage
MODE=integration scripts/regression_loop.sh 3
```

판정:

- `REGRESSION` — 매 반복 실패 (하드 회귀)
- `FLAKY` — 어떤 반복은 통과, 어떤 반복은 실패
- `stable-pass` — 항상 통과

결과: `out/loop-results.json`.

---

## 커버리지 = 동적 백로그

`tests/coverage` 는 카탈로그(87개)와 `scenarios/` 가 실제로 선언한 리소스를 교차검증한다.

```bash
make coverage     # out/coverage.{json,md}
```

두 가지를 회귀로 취급:

1. 시나리오가 카탈로그에 없는 리소스를 참조 → 오타이거나 카탈로그 재동기화 필요.
2. `COVERAGE_MIN` 설정 시 커버리지가 그 % 미만이면 실패 (점진적 ratchet 용).

`out/coverage.md` 의 *Uncovered* 목록이 곧 "아직 회귀 시나리오가 없는 리소스" 백로그다. 오늘 기준 70/87 (80.5%).

### 시나리오 자동 생성 (scripts/gen_scenarios.py)

provider 스키마 덤프(`terraform providers schema -json`)를 읽어, 아직 커버되지 않은 리소스에 대해
**최소 스키마-유효 시나리오를 생성하고 실제 `terraform validate`로 검증한 뒤 통과한 것만** 남긴다.
필수 중첩 블록은 재귀적으로 채우고, enum 검증은 validate 오류("must be one of ...")에서 허용값을
학습해 재시도한다. 그래도 통과 못 하는 리소스(교차필드·정규식 검증 등)는 자동 제외 — 깨진 픽스처는
절대 커밋되지 않는다. 생성물은 `# AUTO-GENERATED` 주석이 달린 스키마 존재/회귀 가드 픽스처로,
손으로 만든 integration 시나리오와 구분된다(필요 시 integration 단언을 덧붙여 승격).

레지스트리가 막힌 환경에서는 provider mirror(`TF_CLI_CONFIG_FILE`)가 필요하다. CI에는 생성
스크립트가 아니라 **검증을 통과한 시나리오 산출물**만 커밋된다.

### 카탈로그 갱신

provider가 새 리소스를 추가하면 `config/scp_resources.json` 의 `resources` 배열을 registry
`docs/resources` 인덱스 기준으로 갱신하고 `latest_version_seen` / `catalog_synced_at` 를 올린다.

---

## 빠른 사용 요약

```bash
make discover                 # 무엇이 발견되는지 확인
make test                     # 챕터별 팬아웃 → 취합 (dry-run)
make coverage                 # 리소스 커버리지 리포트
make loop ITER=5              # 반복 회귀 + flaky 분류
make merge                    # 샤드 수동 취합 (out/results.json + junit.xml)
```
