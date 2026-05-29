package schema

import (
	"testing"

	"github.com/kyle-agent/terraform-test-automation/tests/common"
)

// TestScenarios_ValidateAll is a dynamic schema-regression guard: it discovers
// every scenario under scenarios/ at run time and runs `terraform validate`
// against each as an isolated sub-test. No credentials and no cloud calls are
// needed, so it runs in dry-run on every PR.
//
// A failure means a scenario no longer matches the provider schema — i.e. a new
// provider release renamed/removed an attribute or changed a type. Each
// scenario fails independently (sub-test isolation), so one broken fixture does
// not mask the others. New scenarios are picked up automatically.
func TestScenarios_ValidateAll(t *testing.T) {
	defer common.Wrap(t, common.CaseMeta{
		Name:     t.Name(),
		Chapter:  "schema",
		IssueRef: "kyle-agent/terraform-test-automation (dynamic schema validate)",
		Severity: "high",
		Summary:  "every scenario must match the provider schema (terraform validate)",
	})()

	if !common.TerraformAvailable() {
		t.Skip("terraform not installed; schema validate skipped (CI installs it)")
	}

	scenarios, err := common.ListScenarioDirs()
	if err != nil {
		t.Fatalf("discover scenarios: %v", err)
	}
	if len(scenarios) == 0 {
		t.Fatal("no scenarios discovered under scenarios/")
	}

	for _, name := range scenarios {
		name := name
		t.Run(name, func(t *testing.T) {
			common.Validate(t, common.ScenarioPath(name))
		})
	}
}
