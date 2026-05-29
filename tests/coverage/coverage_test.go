package coverage

import (
	"os"
	"strconv"
	"testing"

	"github.com/kyle-agent/terraform-test-automation/tests/common"
)

// TestCoverage_ResourceSurface is a dynamic, dependency-free guard that runs in
// every mode (no terraform / no credentials needed). It cross-references the
// provider's real resource surface (config/scp_resources.json) against the
// resources that the scenarios under scenarios/ actually declare, and writes a
// coverage report to out/coverage.{json,md}.
//
// Two failure modes are treated as regressions:
//
//  1. A scenario references a resource that is NOT in the catalog. That almost
//     always means a typo or that the catalog needs a registry re-sync — either
//     way the suite is testing something that doesn't line up with the provider.
//
//  2. Coverage drops below COVERAGE_MIN (percent). This is opt-in: the gate is
//     only enforced when COVERAGE_MIN is set, so day-to-day runs stay
//     report-only while CI can ratchet the floor up over time.
//
// This is the "dynamically discover problems" entry point of the suite: as the
// provider grows (87+ resources today) the uncovered list is the live backlog
// of what regression scenarios still need to be written.
func TestCoverage_ResourceSurface(t *testing.T) {
	defer common.Wrap(t, common.CaseMeta{
		Name:     t.Name(),
		Chapter:  "coverage",
		IssueRef: "kyle-agent/terraform-test-automation (dynamic coverage)",
		Severity: "medium",
		Summary:  "regression scenario coverage vs provider resource surface",
	})()

	cat, err := common.LoadResourceCatalog()
	if err != nil {
		t.Fatalf("load resource catalog: %v", err)
	}
	if len(cat.Resources) == 0 {
		t.Fatal("resource catalog is empty; refresh config/scp_resources.json")
	}

	scenarioResources, err := common.ScanScenarioResources()
	if err != nil {
		t.Fatalf("scan scenarios: %v", err)
	}

	cov := common.ComputeCoverage(cat, scenarioResources)
	mdPath, err := common.WriteCoverageReport(cov, cat)
	if err != nil {
		t.Fatalf("write coverage report: %v", err)
	}
	t.Logf("provider %s (v%s): covered %d/%d resources (%.1f%%) — report: %s",
		cat.Provider.Source, cat.Provider.LatestVersionSeen,
		len(cov.Covered), cov.Total, cov.Percent, mdPath)
	for _, r := range cov.Covered {
		t.Logf("  covered: %s", r)
	}

	// Regression 1: scenarios must only reference resources the provider exposes.
	if len(cov.Unknown) > 0 {
		t.Errorf("scenarios reference %d resource(s) not in the catalog (typo, or catalog needs re-sync): %v",
			len(cov.Unknown), cov.Unknown)
	}

	// Regression 2: optional coverage floor.
	if min := os.Getenv("COVERAGE_MIN"); min != "" {
		floor, perr := strconv.ParseFloat(min, 64)
		if perr != nil {
			t.Fatalf("invalid COVERAGE_MIN=%q: %v", min, perr)
		}
		if cov.Percent < floor {
			t.Errorf("coverage %.1f%% is below COVERAGE_MIN=%.1f%% — add scenarios for: %v",
				cov.Percent, floor, cov.Uncovered)
		}
	}
}
