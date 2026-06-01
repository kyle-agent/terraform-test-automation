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
	"crypto/sha1"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
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
//
// Every invocation injects TF_VAR_name_suffix=<RunSuffix()> so scenarios that
// incorporate the suffix into their resource names get a per-run-unique name.
// Undeclared in a scenario, the var is simply ignored by terraform; declared
// with a default of "", behavior is unchanged when the suffix is empty.
func TFRun(t *testing.T, dir string, args ...string) (string, error) {
	t.Helper()
	cmd := exec.Command("terraform", args...)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(),
		"TF_IN_AUTOMATION=1", "TF_INPUT=0",
		"TF_VAR_name_suffix="+RunSuffix(),
	)
	out, err := cmd.CombinedOutput()
	return string(out), err
}

var (
	runSuffixOnce sync.Once
	runSuffixVal  string
)

// RunSuffix returns a short, name-safe ([a-f0-9]) token that is stable for the
// lifetime of the process but unique across CI runs. Scenarios append it to
// fixed resource names so a leak from a previous run (a best-effort destroy
// that failed) can't collide with this run's create — which otherwise surfaces
// as a perpetual, misattributed "apply failed / already exists" regression.
func RunSuffix() string {
	runSuffixOnce.Do(func() {
		// Prefer CI run identifiers so all scenarios in one workflow run share a
		// suffix (stable within the run); fall back to a process-start nonce.
		base := os.Getenv("GITHUB_RUN_ID") + "-" + os.Getenv("GITHUB_RUN_ATTEMPT")
		if strings.Trim(base, "-") == "" {
			base = strconv.FormatInt(time.Now().UnixNano(), 36)
		}
		h := sha1.Sum([]byte(base))
		runSuffixVal = hex.EncodeToString(h[:])[:6]
	})
	return runSuffixVal
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
		// before/after let us name *which* attributes differ on a non-idempotent
		// re-plan (the root-cause signal), not just that the resource changed.
		Before map[string]json.RawMessage `json:"before"`
		After  map[string]json.RawMessage `json:"after"`
		// replace_paths names the attribute(s) that force a destroy+create — the
		// precise culprit for `-/+` replacements (e.g. keypair key material).
		ReplacePaths []json.RawMessage `json:"replace_paths"`
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
		// A failed destroy leaks a real cloud resource. Don't fail the test (the
		// assertion already ran), but surface it in the structured result so the
		// leak is visible and cleanable instead of silently swallowed — a leaked
		// fixed-name resource is what makes a later run's create collide.
		AttachDetail(t.Name(), "LEAK: terraform destroy failed (resource not cleaned up): "+tail(out, 20))
		t.Logf("terraform destroy reported error (continuing; leak surfaced in details): %v\n%s", err, out)
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

// ChangedAttrs returns the top-level attribute names whose before != after
// value in a plan change. For a non-idempotent re-plan this names the offending
// attribute(s) (e.g. description, tags) so the provider fix is targeted.
func ChangedAttrs(c ResourceChange) []string {
	seen := map[string]bool{}
	var changed []string
	add := func(k string) {
		if !seen[k] {
			seen[k] = true
			changed = append(changed, k)
		}
	}
	for k, bv := range c.Change.Before {
		if av, ok := c.Change.After[k]; !ok || string(bv) != string(av) {
			add(k)
		}
	}
	for k := range c.Change.After {
		if _, ok := c.Change.Before[k]; !ok {
			add(k)
		}
	}
	sort.Strings(changed)
	return changed
}

// FormatChange is FormatActions enriched with the attribute-level diff and any
// replace paths, so an idempotency failure is diagnosable from the result alone.
func FormatChange(c ResourceChange) string {
	s := FormatActions(c)
	if attrs := ChangedAttrs(c); len(attrs) > 0 {
		s += " attrs=[" + strings.Join(attrs, ",") + "]"
	}
	if len(c.Change.ReplacePaths) > 0 {
		var rp []string
		for _, p := range c.Change.ReplacePaths {
			rp = append(rp, string(p))
		}
		s += " replace=" + strings.Join(rp, ",")
	}
	return s
}
