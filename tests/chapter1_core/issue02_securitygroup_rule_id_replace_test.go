package chapter1_core

import (
	"os"
	"testing"

	"github.com/kyle-agent/terraform-test-automation/tests/common"
)

// TestIssue02_SecurityGroupRule_IdReplace_Regression verifies that creating
// a security group rule and immediately re-running plan/apply with NO config
// changes does NOT produce a destroy+create replacement.
//
// Historical bug: securitygrouprule.go:57 declared the `id` attribute as
// Computed + RequiresReplace() without UseStateForUnknown(). Every subsequent
// plan saw id as "Unknown" → RequiresReplace fired → the resource was
// destroyed and recreated. See provider issue #11 (sub-item 2-A) and fix
// commit 7c3f7fd.
//
// Failure of this test = regression of that bug; the fix has been reverted
// or a similar pattern has been reintroduced on another resource.
func TestIssue02_SecurityGroupRule_IdReplace_Regression(t *testing.T) {
	defer common.Wrap(t, common.CaseMeta{
		Name:     t.Name(),
		Chapter:  "chapter1_core",
		IssueRef: "kyle-agent/terraform-provider-samsungcloudplatformv2#11 (2-A)",
		Severity: "critical",
		Summary:  "id RequiresReplace causes destroy+create on re-apply",
	})()

	common.SkipUnlessIntegration(t, "needs real SCP credentials and a pre-existing security group")

	sgID := os.Getenv("TEST_SECURITY_GROUP_ID")
	if sgID == "" {
		t.Skip("TEST_SECURITY_GROUP_ID not set")
	}
	t.Setenv("TF_VAR_security_group_id", sgID)

	dir := common.ScenarioPath("securitygroup_rule_basic")
	common.MustInit(t, dir)
	defer common.Destroy(t, dir)

	// First apply — creates the rule.
	out := common.Apply(t, dir)
	common.AssertNoPanic(t, out)

	// Re-plan with no config change.
	plan := common.Plan(t, dir)
	common.AssertNoChanges(t, plan)
	common.AssertNoReplacement(t, plan)
}
