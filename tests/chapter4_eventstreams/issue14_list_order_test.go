package chapter4_eventstreams

import (
	"os"
	"testing"

	"github.com/kyle-agent/terraform-test-automation/tests/common"
)

// TestIssue14_EventStreams_AllowableIpList_OrderDiff verifies that the
// `allowable_ip_addresses` list does not produce spurious diff (or worse,
// destroy+create) when the API returns the items in a different order than
// the user's config.
//
// Historical bug: eventstreams/cluster.go:59-64 declared the attribute as
// schema.ListAttribute (order-sensitive) and MapGetResponseToState used API
// response order without sorting. Re-plan showed `- "10.0.0.0/8"` for one of
// the entries even though config was unchanged, which combined with a tainted
// state flag caused destroy+create. See provider issue #14 (sub-item 14-A).
//
// Failure of this test means the SetAttribute conversion has been reverted
// or the sort fallback has been removed.
func TestIssue14_EventStreams_AllowableIpList_OrderDiff(t *testing.T) {
	defer common.Wrap(t, common.CaseMeta{
		Name:     t.Name(),
		Chapter:  "chapter4_eventstreams",
		IssueRef: "kyle-agent/terraform-provider-samsungcloudplatformv2#14 (14-A)",
		Severity: "critical",
		Summary:  "allowable_ip_addresses list order causes spurious diff/replace",
	})()

	common.SkipUnlessIntegration(t, "creates a real eventstreams cluster")

	for _, k := range []string{
		"TEST_SUBNET_ID", "TEST_SECURITY_GROUP_ID",
		"TEST_DBAAS_ENGINE_VERSION_ID", "TEST_SERVER_TYPE_NAME",
		"TEST_VPC_ID",
	} {
		if os.Getenv(k) == "" {
			t.Skipf("%s not set", k)
		}
	}
	t.Setenv("TF_VAR_subnet_id", os.Getenv("TEST_SUBNET_ID"))
	t.Setenv("TF_VAR_security_group_id", os.Getenv("TEST_SECURITY_GROUP_ID"))
	t.Setenv("TF_VAR_dbaas_engine_version_id", os.Getenv("TEST_DBAAS_ENGINE_VERSION_ID"))
	t.Setenv("TF_VAR_server_type_name", os.Getenv("TEST_SERVER_TYPE_NAME"))
	t.Setenv("TF_VAR_vpc_id", os.Getenv("TEST_VPC_ID"))

	dir := common.ScenarioPath("eventstreams_basic")
	common.MustInit(t, dir)
	defer common.Destroy(t, dir)

	out := common.Apply(t, dir)
	common.AssertNoPanic(t, out)

	plan := common.Plan(t, dir)
	common.AssertNoChanges(t, plan)
	common.AssertNoReplacement(t, plan)

	// Negative assertion: the tainted-replacement message must not appear.
	common.AssertOutputAbsent(t, plan.RawOutput, "is tainted, so must be replaced")
}
