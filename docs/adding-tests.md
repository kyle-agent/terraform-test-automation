# 새 회귀 테스트 추가하기

## 절차

1. provider 리포의 sub-issue 식별 (예: `#14 (14-A)`)
2. `scenarios/<scenario_name>/main.tf` 작성
   - 결함을 가장 단순하게 재현할 최소 구성
   - 변수는 환경변수(`TEST_*`)로 주입
3. `tests/<chapter>/issueNN_xxx_test.go` 작성
   - 함수명은 `TestIssueNN_…` 패턴
   - `common.Wrap()` 데코레이터로 메타 기록
   - dry-run에서 검증 가능한 부분은 dry-run에 두고, 실 자원이 꼭 필요하면 `common.SkipUnlessIntegration` 사용
4. `docs/test-catalog.md` 한 줄 추가 (상태 = 작성됨)
5. 로컬 검증: `make test-one TEST=TestIssueNN_…`
6. PR 생성 → CI dry-run green 확인 → 머지

## 권장 단언

| 결함 유형 | 단언 |
|---|---|
| 변경 없는 재실행에서 plan에 변화 발생 | `common.AssertNoChanges` |
| 의도치 않은 destroy+create | `common.AssertNoReplacement` |
| panic 회귀 | `common.AssertNoPanic` |
| 특정 에러 메시지가 떠야 함 / 뜨면 안 됨 | `common.AssertOutputContains`, `common.AssertOutputAbsent` |
| 특정 진단 카테고리 부재 | `common.AssertDiagnosticAbsent` |

## 안티패턴

- 한 테스트에서 여러 결함 검증 → 회귀 시 어느 결함이 깨졌는지 모호
- integration 전제 테스트를 dry-run에서도 강제로 통과시키려 함 → 테스트 가치 0
- 시간 의존 테스트(`time.Sleep`)로 stall 검증 → context.Deadline 기반 표준화 패턴 사용

## 메타 필드 가이드

```go
defer common.Wrap(t, common.CaseMeta{
    Name:     t.Name(),
    Chapter:  "chapter4_eventstreams",                                  // 디렉터리명과 동일
    IssueRef: "kyle-agent/terraform-provider-samsungcloudplatformv2#14 (14-A)",
    Severity: "critical",                                               // critical | high | medium
    Summary:  "한 줄 설명 — 회귀 시 issue 코멘트에 그대로 들어감",
})()
```

`IssueRef`의 `(서브태그)`가 publish_report.sh의 코멘트에 표시된다.
