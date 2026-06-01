// Package common provides shared helpers for regression tests.
//
// The helpers wrap the terraform CLI so individual tests can stay short and
// focused on the *symptom* they are verifying.
//
// Modes:
//   - dry-run     : terraform init + plan only. No cloud resources are touched.
//                   Used to detect schema-level regressions (e.g. spurious
//                   destroy+create plans, missing fields, validator gaps).
//   - integration : terraform init + apply + assertions + destroy. Requires
//                   real SCP credentials in the environment.
package common

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// Mode returns the test execution mode.
func Mode() string {
	m := strings.ToLower(os.Getenv("MODE"))
	if m == "" {
		return "dry-run"
	}
	return m
}

// IsIntegration reports whether the current run is allowed to touch the cloud.
func IsIntegration() bool { return Mode() == "integration" || Mode() == "canary" }

// SkipUnlessIntegration skips the calling test if not in integration mode.
func SkipUnlessIntegration(t *testing.T, reason string) {
	t.Helper()
	if !IsIntegration() {
		t.Skipf("skipping (requires MODE=integration): %s", reason)
	}
}

// TFRun executes terraform in the given scenario directory.
// Returns combined stdout+stderr and any exec error. The error is non-nil if
// terraform exits non-zero — callers should inspect both error and output.
func TFRun(t *testing.T, dir string, args ...string) (string, error) {
	t.Helper()
	cmd := exec.Command("terraform", args...)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(), "TF_IN_AUTOMATION=1", "TF_INPUT=0")
	out, err := cmd.CombinedOutput()
	return string(out), err
}

// MustInit runs `terraform init` and fails the test on error.
func MustInit(t *testing.T, dir string) {
	t.Helper()
	out, err := TFRun(t, dir, "init", "-no-color", "-input=false")
	if err != nil {
		t.Fatalf("terraform init failed in %s: %v\n%s", dir, err, out)
	}
}

// PlanResult is the parsed -json output of `terraform plan`.
type PlanResult struct {
	RawOutput        string
	ResourceChanges  []ResourceChange
	Diagnostics      []Diagnostic
}

// ResourceChange mirrors the relevant subset of terraform's plan json schema.
type ResourceChange struct {
	Address string `json:"address"`
	Change  struct {
		Actions []string `json:"actions"` // ["no-op"], ["create"], ["update"], ["delete"], ["delete","create"]
	} `json:"change"`
}

// Diagnostic mirrors terraform diagnostics in json output.
type Diagnostic struct {
	Severity string `json:"severity"`
	Summary  string `json:"summary"`
	Detail   string `json:"detail"`
}

// Plan runs `terraform plan` and returns a parsed result. In dry-run mode
// this is the primary signal for detecting schema regressions.
func Plan(t *testing.T, dir string) PlanResult {
	t.Helper()
	planPath := filepath.Join(dir, "out.tfplan")
	out, err := TFRun(t, dir, "plan", "-no-color", "-input=false", "-out="+planPath)
	res := PlanResult{RawOutput: out}
	if err != nil {
		// Plan errored. Record the failing tail so a later assertion failure is
		// diagnosable from results.json alone (an empty plan otherwise looks
		// like a silent no-op and the CI log has to be scraped by hand).
		AttachDetail(t.Name(), "terraform plan failed: "+tail(out, 30))
		// Still parse diagnostics from text output for error tests
		return res
	}
	showOut, _ := TFRun(t, dir, "show", "-json", planPath)
	var raw struct {
		ResourceChanges []ResourceChange `json:"resource_changes"`
	}
	if jerr := json.Unmarshal([]byte(showOut), &raw); jerr == nil {
		res.ResourceChanges = raw.ResourceChanges
	}
	return res
}

// Apply runs `terraform apply` (auto-approve). Skips in dry-run mode.
func Apply(t *testing.T, dir string) string {
	t.Helper()
	if !IsIntegration() {
		t.Skip("apply requires MODE=integration")
	}
	out, err := TFRun(t, dir, "apply", "-no-color", "-input=false", "-auto-approve")
	if err != nil {
		// Capture the failing tail into the structured result before Fatalf so
		// the auto-filed regression issue shows *what* failed (an apply error,
		// e.g. a create/validation failure) instead of an empty "details: —".
		AttachDetail(t.Name(), "terraform apply failed: "+tail(out, 30))
		t.Fatalf("terraform apply failed in %s: %v\n%s", dir, err, out)
	}
	return out
}

// tail returns the last n non-empty lines of s, trimmed, for compact inclusion
// in a structured result (the full log stays in the CI output / RawOutput).
func tail(s string, n int) string {
	lines := strings.Split(strings.TrimRight(s, "\n"), "\n")
	var kept []string
	for i := len(lines) - 1; i >= 0 && len(kept) < n; i-- {
		if strings.TrimSpace(lines[i]) != "" {
			kept = append([]string{strings.TrimSpace(lines[i])}, kept...)
		}
	}
	return strings.Join(kept, " ⏎ ")
}

// Destroy runs `terraform destroy` (auto-approve). Safe to defer.
func Destroy(t *testing.T, dir string) {
	t.Helper()
	if !IsIntegration() {
		return
	}
	out, err := TFRun(t, dir, "destroy", "-no-color", "-input=false", "-auto-approve")
	if err != nil {
		t.Logf("terraform destroy reported error (continuing): %v\n%s", err, out)
	}
}

// ScenarioPath returns the absolute path of a scenario directory relative to
// the repo root. Tests should use this so they can be invoked from any cwd.
func ScenarioPath(name string) string {
	// Resolve relative to this file at compile-time would be ideal, but tests
	// are invoked from arbitrary cwd. We use a sentinel walk-up.
	base, err := os.Getwd()
	if err != nil {
		return name
	}
	dir := base
	for i := 0; i < 6; i++ {
		candidate := filepath.Join(dir, "scenarios", name)
		if _, err := os.Stat(candidate); err == nil {
			return candidate
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	return filepath.Join(base, "scenarios", name)
}

// FormatActions joins resource change actions for log readability.
func FormatActions(c ResourceChange) string {
	return fmt.Sprintf("%s -> %s", c.Address, strings.Join(c.Change.Actions, ","))
}
