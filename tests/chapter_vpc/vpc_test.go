package chapter_vpc

import (
	"os"
	"testing"

	"github.com/kyle-agent/terraform-test-automation/tests/common"
)

// TestVpc_Vpc_Idempotent verifies that creating a VPC and immediately
// re-running plan/apply with NO config changes produces a clean plan: no
// spurious update and no destroy+create replacement.
//
// This guards the baseline networking resource against the same class of
// idempotency regression seen on other resources (computed id plumbed with
// RequiresReplace, unstable defaults, etc.). A failure means a re-apply with
// unchanged config is no longer a no-op.
func TestVpc_Vpc_Idempotent(t *testing.T) {
	defer common.Wrap(t, common.CaseMeta{
		Name:     t.Name(),
		Chapter:  "chapter_vpc",
		IssueRef: "kyle-agent/terraform-test-automation (vpc coverage)",
		Severity: "medium",
		Summary:  "vpc_vpc re-apply with no config change must be a no-op",
	})()

	common.SkipUnlessIntegration(t, "needs real SCP credentials to create a VPC")

	dir := common.ScenarioPath("vpc_vpc")
	common.MustInit(t, dir)
	defer common.Destroy(t, dir)

	// First apply — creates the VPC.
	out := common.Apply(t, dir)
	common.AssertNoPanic(t, out)

	// Re-plan with no config change.
	plan := common.Plan(t, dir)
	common.AssertNoChanges(t, plan)
	common.AssertNoReplacement(t, plan)
}

// TestVpc_Subnet_Idempotent verifies that creating a subnet and immediately
// re-running plan/apply with NO config changes produces a clean plan: no
// spurious update and no destroy+create replacement.
//
// Requires a pre-existing VPC supplied via TEST_VPC_ID (plumbed to the scenario
// as TF_VAR_vpc_id). A failure means a re-apply with unchanged config is no
// longer a no-op for the subnet resource.
func TestVpc_Subnet_Idempotent(t *testing.T) {
	defer common.Wrap(t, common.CaseMeta{
		Name:     t.Name(),
		Chapter:  "chapter_vpc",
		IssueRef: "kyle-agent/terraform-test-automation (vpc coverage)",
		Severity: "medium",
		Summary:  "vpc_subnet re-apply with no config change must be a no-op",
	})()

	common.SkipUnlessIntegration(t, "needs real SCP credentials and a pre-existing VPC")

	vpcID := os.Getenv("TEST_VPC_ID")
	if vpcID == "" {
		t.Skip("TEST_VPC_ID not set")
	}
	t.Setenv("TF_VAR_vpc_id", vpcID)

	dir := common.ScenarioPath("vpc_subnet")
	common.MustInit(t, dir)
	defer common.Destroy(t, dir)

	// First apply — creates the subnet.
	out := common.Apply(t, dir)
	common.AssertNoPanic(t, out)

	// Re-plan with no config change.
	plan := common.Plan(t, dir)
	common.AssertNoChanges(t, plan)
	common.AssertNoReplacement(t, plan)
}

// TestVpc_PublicIp_Idempotent verifies that creating a public IP and
// immediately re-running plan/apply with NO config changes produces a clean
// plan: no spurious update and no destroy+create replacement.
//
// A failure means a re-apply with unchanged config is no longer a no-op for the
// public IP resource.
func TestVpc_PublicIp_Idempotent(t *testing.T) {
	defer common.Wrap(t, common.CaseMeta{
		Name:     t.Name(),
		Chapter:  "chapter_vpc",
		IssueRef: "kyle-agent/terraform-test-automation (vpc coverage)",
		Severity: "medium",
		Summary:  "vpc_publicip re-apply with no config change must be a no-op",
	})()

	common.SkipUnlessIntegration(t, "needs real SCP credentials to allocate a public IP")

	dir := common.ScenarioPath("vpc_publicip")
	common.MustInit(t, dir)
	defer common.Destroy(t, dir)

	// First apply — allocates the public IP.
	out := common.Apply(t, dir)
	common.AssertNoPanic(t, out)

	// Re-plan with no config change.
	plan := common.Plan(t, dir)
	common.AssertNoChanges(t, plan)
	common.AssertNoReplacement(t, plan)
}
