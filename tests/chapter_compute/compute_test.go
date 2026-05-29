package chapter_compute

import (
	"testing"

	"github.com/kyle-agent/terraform-test-automation/tests/common"
)

// TestSecurityGroup_Idempotent verifies that creating a security group and
// immediately re-running plan/apply with NO config changes produces a clean
// plan: no-op, no destroy+create replacement.
//
// This is the security-group analogue of the Chapter 1 #2 rule regression: a
// Computed attribute plumbed with RequiresReplace() but without
// UseStateForUnknown() makes id appear "Unknown" on every plan, firing a
// spurious replacement. Failure here = that class of bug reintroduced on the
// security group resource.
func TestSecurityGroup_Idempotent(t *testing.T) {
	defer common.Wrap(t, common.CaseMeta{
		Name:     t.Name(),
		Chapter:  "chapter_compute",
		IssueRef: "kyle-agent/terraform-test-automation (compute coverage)",
		Severity: "medium",
		Summary:  "security group re-apply must be a clean no-op (no replacement)",
	})()

	common.SkipUnlessIntegration(t, "needs real SCP credentials to create a security group")

	dir := common.ScenarioPath("security_group_basic")
	common.MustInit(t, dir)
	defer common.Destroy(t, dir)

	// First apply — creates the security group.
	out := common.Apply(t, dir)
	common.AssertNoPanic(t, out)

	// Re-plan with no config change: must be a clean no-op.
	plan := common.Plan(t, dir)
	common.AssertNoChanges(t, plan)
	common.AssertNoReplacement(t, plan)
}

// TestVirtualServerKeypair_Idempotent verifies that creating a virtual server
// keypair and immediately re-running plan/apply with NO config changes produces
// a clean plan: no-op, no destroy+create replacement.
//
// Keypairs expose Computed key material; if that material is not stabilized
// with UseStateForUnknown(), a second plan churns (-/+) the keypair, which on a
// real account would rotate the key and break access. Failure here flags that
// regression.
func TestVirtualServerKeypair_Idempotent(t *testing.T) {
	defer common.Wrap(t, common.CaseMeta{
		Name:     t.Name(),
		Chapter:  "chapter_compute",
		IssueRef: "kyle-agent/terraform-test-automation (compute coverage)",
		Severity: "medium",
		Summary:  "keypair re-apply must be a clean no-op (no replacement)",
	})()

	common.SkipUnlessIntegration(t, "needs real SCP credentials to create a keypair")

	dir := common.ScenarioPath("virtualserver_keypair")
	common.MustInit(t, dir)
	defer common.Destroy(t, dir)

	// First apply — creates the keypair.
	out := common.Apply(t, dir)
	common.AssertNoPanic(t, out)

	// Re-plan with no config change: must be a clean no-op.
	plan := common.Plan(t, dir)
	common.AssertNoChanges(t, plan)
	common.AssertNoReplacement(t, plan)
}
