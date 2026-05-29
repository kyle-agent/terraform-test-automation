package chapter2_loadbalancer

import (
	"os"
	"testing"

	"github.com/kyle-agent/terraform-test-automation/tests/common"
)

// TestLoadBalancer_Create_Idempotent verifies that a loadbalancer can be
// created and that an immediate re-plan with unchanged config is idempotent:
// no spurious diff, no destroy+create replacement, and no "is tainted, so must
// be replaced" message.
//
// The loadbalancer resource takes a single nested object attribute
// (`loadbalancer_create`). Object-typed create inputs are a common source of
// re-plan churn — if the provider's Read does not faithfully round-trip every
// object field, a subsequent plan shows an update (or worse, replacement) even
// though the user changed nothing. This guards the Chapter 2 / provider
// issue #12 loadbalancer family against that class of regression.
//
// The dry-run schema sweep already covers `terraform validate`, so this test is
// integration-only. Because the subnet/vpc ids live inside the object variable,
// the integration variant uses the scenario defaults unless the operator
// overrides them (e.g. via TF_VAR_loadbalancer); TEST_SUBNET_ID / TEST_VPC_ID
// are still required as a guard so the test only runs in a properly provisioned
// integration environment.
func TestLoadBalancer_Create_Idempotent(t *testing.T) {
	defer common.Wrap(t, common.CaseMeta{
		Name:     t.Name(),
		Chapter:  "chapter2_loadbalancer",
		IssueRef: "kyle-agent/terraform-provider-samsungcloudplatformv2#12 (LB family)",
		Severity: "high",
		Summary:  "loadbalancer create + idempotent re-plan (no spurious diff/replace)",
	})()

	common.SkipUnlessIntegration(t, "creates a real loadbalancer")

	for _, k := range []string{"TEST_SUBNET_ID", "TEST_VPC_ID"} {
		if os.Getenv(k) == "" {
			t.Skipf("%s not set", k)
		}
	}

	dir := common.ScenarioPath("loadbalancer_basic")
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
