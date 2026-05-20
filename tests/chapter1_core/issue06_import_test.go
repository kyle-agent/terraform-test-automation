package chapter1_core

import (
	"os"
	"testing"

	"github.com/kyle-agent/terraform-test-automation/tests/common"
)

// TestIssue06_ImportState_Coverage exercises `terraform import` on the small
// subset of resources that ARE expected to support ImportState. Today only
// multinodegpucluster gpunode_resource implements it (and even that is
// missing the interface assertion). The test should grow as #6-B (other 83
// resources) is implemented; each new resource fix adds a sub-test here.
//
// In dry-run mode the test only validates that the import command parses
// (catches "Resource does not support import" before the user does).
func TestIssue06_ImportState_Coverage(t *testing.T) {
	defer common.Wrap(t, common.CaseMeta{
		Name:     t.Name(),
		Chapter:  "chapter1_core",
		IssueRef: "kyle-agent/terraform-provider-samsungcloudplatformv2#11 (6-A/6-B)",
		Severity: "high",
		Summary:  "ImportState coverage tracking — fails when supported set regresses",
	})()

	cases := []struct {
		resource string
		envID    string // env var holding a real id to import
	}{
		{"samsungcloudplatformv2_multinodegpucluster_gpunode", "TEST_GPUNODE_ID"},
		// Add more here as #6-B lands:
		// {"samsungcloudplatformv2_virtualserver_server", "TEST_SERVER_ID"},
		// {"samsungcloudplatformv2_mysql_cluster",        "TEST_MYSQL_ID"},
	}

	for _, c := range cases {
		t.Run(c.resource, func(t *testing.T) {
			common.SkipUnlessIntegration(t, "real import requires an existing resource id")
			id := os.Getenv(c.envID)
			if id == "" {
				t.Skipf("%s not set", c.envID)
			}
			dir := common.ScenarioPath("import_smoke")
			common.MustInit(t, dir)
			defer common.Destroy(t, dir)
			out, err := common.TFRun(t, dir, "import", c.resource+".target", id)
			common.AssertNoPanic(t, out)
			common.AssertOutputAbsent(t, out, "does not support import")
			if err != nil {
				t.Fatalf("import failed: %v\n%s", err, out)
			}
		})
	}
}
