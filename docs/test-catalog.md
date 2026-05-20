# Test Catalog

provider 리포의 sub-issue ↔ 회귀 테스트 매핑.

PR 형태로 새 fix가 들어오면 이 표에 한 줄을 추가하고, `tests/<chapter>/` 에 테스트를 작성한 뒤 PR을 올린다.

## Chapter 1 — Core Provider 결함 ([#11](https://github.com/kyle-agent/terraform-provider-samsungcloudplatformv2/issues/11))

| Sub | 결함 | 테스트 | 상태 |
|---|---|---|---|
| 1-A~E | DB 폴링 transient 미재시도 | `TestIssue01_DB_PollingTransientRetry` | TODO |
| 2-A | id RequiresReplace ✅ | `TestIssue02_SecurityGroupRule_IdReplace_Regression` | 작성됨 |
| 3-A~G | DB Update 핸들러 누락 diff | `TestIssue03_DB_Update_HandlerMissing_Diff` | TODO |
| 4-A/B | SKE advanced_settings 사후 요구 | `TestIssue04_SKE_AdvancedSettings_RequiredOnRerun` | TODO |
| 5-A | securitygrouprule.go Update panic | `TestIssue05_SecurityGroupRule_Panic_OnUpdate` | TODO |
| 5-B~H | 슬라이스 panic | `TestD01_SliceIndex_Panic_Multi` | TODO |
| 6-A/B | ImportState 미지원 | `TestIssue06_ImportState_Coverage` | 작성됨(스켈레톤) |

## Chapter 2 — LB/Routing ([#12](https://github.com/kyle-agent/terraform-provider-samsungcloudplatformv2/issues/12))

| Sub | 결함 | 테스트 | 상태 |
|---|---|---|---|
| 7-A~H | Required 과다 (default 부재) | `TestIssue07_RequiredDefaults_*` | TODO |
| 8-A | UpdateLbListener nil 미검사 | `TestIssue08A_LbListener_UrlHandler_Nil` | TODO |
| 8-C | Create 후 ACTIVE 미대기 | `TestIssue08C_LbListener_NoActiveWait` | TODO |
| 8-D | InsertClientIp IsSet 오용 | `TestIssue08D_LbListener_InsertClientIp_IsSetMisuse` | TODO |
| 9-A~D | Target Type IP 미지원 | `TestIssue09_LbMember_TargetTypeIP` | TODO |
| 10-A~D | L7 protocol 104 | `TestIssue10_LbListener_Protocol_104` | TODO |

## Chapter 3 — Provider Configure ([#13](https://github.com/kyle-agent/terraform-provider-samsungcloudplatformv2/issues/13))

| Sub | 결함 | 테스트 | 상태 |
|---|---|---|---|
| 11-A | HTTP timeout 주석 | `TestIssue11_Configure_HttpTimeout_CommentedOut` | 작성됨(스켈레톤) |
| 12-A | Service Check stall | `TestIssue12_ServiceCheck_StallOnSlowEndpoint` | TODO |
| 13-A | IAM endpoint retry 부재 | `TestIssue13_GetEndpointList_NoRetry` | TODO |

## Chapter 4 — EventStreams ([#14](https://github.com/kyle-agent/terraform-provider-samsungcloudplatformv2/issues/14))

| Sub | 결함 | 테스트 | 상태 |
|---|---|---|---|
| 14-A/B | allowable_ip_addresses List 순서 | `TestIssue14_EventStreams_AllowableIpList_OrderDiff` | 작성됨 |
| 15-A/B | nested list 순서 | `TestIssue15_EventStreams_NestedList_Order` | TODO |
| 16-A~C | Create 부분 실패 orphan | `TestIssue16_EventStreams_PartialCreate_Orphan` | TODO |

## Chapter 5 — FileStorage ([#15](https://github.com/kyle-agent/terraform-provider-samsungcloudplatformv2/issues/15))

| Sub | 결함 | 테스트 | 상태 |
|---|---|---|---|
| 17-A~D | access_rules 외부 추가 항목 삭제 | `TestIssue17_FileStorage_ExternalRule_Deleted` | TODO |
| 18-A | per-rule sub-resource 부재 | `TestIssue18_FileStorage_PerRuleResource_Available` | TODO (fix 이후) |

## Chapter 6 — Object Storage Backend ([#16](https://github.com/kyle-agent/terraform-provider-samsungcloudplatformv2/issues/16))

| Sub | 결함 | 테스트 | 상태 |
|---|---|---|---|
| 19-A | auth_token 사용 가이드 회귀 | `TestIssue19_Backend_AuthToken_Documented` | TODO |
| 20-A/B | Keyless 가이드 회귀 | `TestIssue20_Backend_Keyless_Documented` | TODO |

## Chapter 7 — 문서·예제 ([#17](https://github.com/kyle-agent/terraform-provider-samsungcloudplatformv2/issues/17))

| Sub | 결함 | 테스트 | 상태 |
|---|---|---|---|
| 21-A | Example Usage 누락 회귀 | `TestIssue21_Docs_ExampleUsage_Present` | TODO |
| 22-C | 스텁 description lint | `TestIssue22_Docs_StubDescription_Count` | TODO |
| 23-C | example 커버리지 ≥ 80% | `TestIssue23_Docs_ExampleCoverage` | TODO |

## Deep Audit ([#18](https://github.com/kyle-agent/terraform-provider-samsungcloudplatformv2/issues/18))

| Sub | 결함 | 테스트 | 상태 |
|---|---|---|---|
| D-1 | 빈 리스트 인덱싱 다발 | `TestD01_SliceIndex_Panic_Multi` | TODO |
| D-2 | lblistener map type assertion | `TestD02_LbListener_MapAssertion_SilentDrop` | TODO |
| D-3 | lbmember state-before-wait | `TestD03_LbMember_StateBeforeWait` | TODO |
| D-5 | BareMetal IOPS=0 | `TestD05_BareMetal_IopsParseSilent` | TODO |
| D-9 | 404 문자열 매칭 | `TestD09_NotFound_StringMatching` | TODO |
| D-15 | timeout 단일 정책 | `TestD15_Timeout_Uniform120m` | TODO |
| D-18 | Delete 멱등성 | `TestD18_Delete_Idempotent` | TODO |
| D-20 | Empty ResourceId | `TestD20_ResourceId_Empty` | TODO |
