// Package capability builds a general "what works / what doesn't" matrix across
// every provider resource scenario, rather than per-chapter pass/fail.
//
// For each scenario under scenarios/ it walks a fixed pipeline of stages and
// records the outcome of each stage independently:
//
//	validate -> plan -> apply -> replan(idempotency) -> destroy
//
// Each stage is one of: ok / fail / skip. A later stage is skipped when an
// earlier one did not succeed, or when the environment can't support it
// (e.g. apply needs MODE=integration; validate/plan need a terraform binary
// and an installable provider). The result is written to:
//
//	out/capability-matrix.json   (machine-readable)
//	out/capability-matrix.md     (resource x stage table + per-stage tally)
//
// This is the "general frame" — run it first to see which resources work and
// which fail at which stage, then drill into specific cases. It is opt-in so
// it never runs in the normal suite: set CAPABILITY_MATRIX=1.
//
//	CAPABILITY_MATRIX=1 go test ./tests/capability/... -run TestCapabilityMatrix -timeout 120m
//
// In dry-run it fills validate/plan only (apply/replan/destroy => skip), which
// is safe and credential-free. In MODE=integration it exercises the full
// lifecycle against real cloud resources.
package capability

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"

	"github.com/kyle-agent/terraform-test-automation/tests/common"
)

func TestCapabilityMatrix(t *testing.T) {
	if os.Getenv("CAPABILITY_MATRIX") == "" {
		t.Skip("opt-in: set CAPABILITY_MATRIX=1 to build the capability matrix")
	}

	scenarios, err := common.ListScenarioDirs()
	if err != nil {
		t.Fatalf("discover scenarios: %v", err)
	}

	// MATRIX_SCENARIOS (comma-separated) restricts the run to specific scenarios.
	// The full integration matrix walks all 87 resources sequentially through the
	// whole lifecycle, which takes hours and risks timing out / leaking heavyweight
	// clusters; an on-demand run can scope to just the resources under
	// investigation while the scheduled run stays full.
	if sel := strings.TrimSpace(os.Getenv("MATRIX_SCENARIOS")); sel != "" {
		want := map[string]bool{}
		for _, s := range strings.Split(sel, ",") {
			if s = strings.TrimSpace(s); s != "" {
				want[s] = true
			}
		}
		var filtered []string
		for _, n := range scenarios {
			if want[n] {
				filtered = append(filtered, n)
			}
		}
		scenarios = filtered
		t.Logf("MATRIX_SCENARIOS set: restricting matrix to %d scenario(s): %v", len(scenarios), scenarios)
	}

	var caps []ResourceCaps
	for _, name := range scenarios {
		name := name
		t.Run(name, func(t *testing.T) {
			rc := runScenario(t, name)
			caps = append(caps, rc)
		})
	}

	sort.Slice(caps, func(i, j int) bool { return caps[i].Scenario < caps[j].Scenario })
	if err := writeMatrix(caps); err != nil {
		t.Fatalf("write matrix: %v", err)
	}
	t.Logf("capability matrix written for %d scenarios", len(caps))
}

// runScenario walks the pipeline for a single scenario, never failing the test
// itself — every stage outcome is recorded so the matrix is complete.
func runScenario(t *testing.T, name string) ResourceCaps {
	rc := ResourceCaps{
		Scenario: name,
		Resource: scenarioResource(name),
		Stages:   map[string]string{},
	}
	for _, s := range stageNames {
		rc.Stages[s] = "skip"
	}

	dir := common.ScenarioPath(name)

	// Intentionally-partial fixtures opt out of the whole pipeline.
	if common.ScenarioOptsOutOfValidate(name) {
		rc.Note = "regr:no-validate (intentionally partial fixture)"
		return rc
	}
	if !common.TerraformAvailable() {
		rc.Note = "terraform not installed"
		return rc
	}

	// --- validate (init + validate) ---
	if out, err := common.TFRun(t, dir, "init", "-backend=false", "-no-color", "-input=false"); err != nil {
		if providerInstallBlocked(out) {
			rc.Note = "provider not installable (registry blocked/offline)"
			return rc // validate stays skip
		}
		rc.Stages["validate"] = "fail"
		rc.Note = firstError(out)
		return rc
	}
	vout, _ := common.TFRun(t, dir, "validate", "-no-color", "-json")
	if !validateOK(vout) {
		rc.Stages["validate"] = "fail"
		rc.Note = firstError(vout)
		return rc
	}
	rc.Stages["validate"] = "ok"

	// plan and beyond require a configured provider (Auth URL + credentials),
	// so they are only meaningful in integration mode. In dry-run we stop at
	// validate — measuring plan without credentials would just report "missing
	// Auth URL" for every resource, which is noise, not a capability signal.
	if !common.IsIntegration() {
		rc.Note = "plan/apply/replan/destroy need MODE=integration (credentials)"
		return rc
	}

	// --- plan ---
	plan := common.Plan(t, dir)
	if plan.RawOutput != "" && strings.Contains(plan.RawOutput, "Error:") && len(plan.ResourceChanges) == 0 {
		// Distinguish a provider-init/Configure failure (e.g. IAM endpoint list)
		// from a real plan defect: the former is tracked as provider #38/#37 and
		// must not be filed as a resource regression.
		if common.IsProviderInitTransient(plan.RawOutput) {
			rc.Stages["plan"] = "blocked"
			rc.Note = "provider-init transient, see provider #38: " + firstError(plan.RawOutput)
			return rc
		}
		rc.Stages["plan"] = "fail"
		rc.Note = firstError(plan.RawOutput)
		return rc
	}
	rc.Stages["plan"] = "ok"

	out, err := common.TFRun(t, dir, "apply", "-no-color", "-input=false", "-auto-approve")
	if err != nil {
		if common.IsProviderInitTransient(out) {
			rc.Stages["apply"] = "blocked"
			rc.Note = "provider-init transient, see provider #38: " + firstError(out)
			return rc
		}
		rc.Stages["apply"] = "fail"
		rc.Note = firstError(out)
		// Best-effort cleanup: a partial apply may have already created some
		// resources (e.g. a parent created before a dependent child failed).
		// terraform skips them otherwise, leaking real cloud resources. Destroy
		// what made it into state; surface a LEAK marker if that also fails.
		if dout, derr := common.TFRun(t, dir, "destroy", "-no-color", "-input=false", "-auto-approve"); derr != nil {
			rc.Note += " | LEAK: partial-create cleanup destroy failed: " + firstError(dout)
		}
		return rc
	}
	rc.Stages["apply"] = "ok"

	// re-plan: a clean re-plan (no changes) is the idempotency capability.
	replan := common.Plan(t, dir)
	if idempotent(replan) {
		rc.Stages["replan"] = "ok"
	} else {
		rc.Stages["replan"] = "fail"
		rc.Note = "non-idempotent: " + changedSummary(replan)
	}

	// --- update (OPTIONAL, gated by MATRIX_UPDATE=1) ---
	// After a clean apply+replan, re-apply with scenarios/<name>/update.tfvars
	// (which mutates a safe, in-place-updatable attribute) and require the
	// re-apply to succeed AND a subsequent re-plan to be clean. This catches
	// in-place Update defects (cf. provider #71/#72) that the create-only
	// pipeline never exercises. Stays "skip" when the gate is unset or the
	// scenario has no update.tfvars.
	runUpdateStage(t, dir, name, &rc)

	// --- import (OPTIONAL, gated by MATRIX_IMPORT=1) ---
	// Read the primary resource's address+id from `terraform show -json`, then in
	// a throwaway copy+state run `terraform import <addr> <id>`. A resource that
	// does not implement ImportState records "unsupported" (NOT "fail") — that is
	// the #4 gap, surfaced per-resource rather than a defect of this run.
	runImportStage(t, dir, name, &rc)

	// destroy regardless of replan outcome, and record whether cleanup worked.
	if dout, derr := common.TFRun(t, dir, "destroy", "-no-color", "-input=false", "-auto-approve"); derr != nil {
		rc.Stages["destroy"] = "fail"
		if rc.Note == "" {
			rc.Note = "destroy failed: " + firstError(dout)
		}
	} else {
		rc.Stages["destroy"] = "ok"
	}
	return rc
}

// changedSummary lists the non-noop resource changes in a plan, for the note.
func changedSummary(plan common.PlanResult) string {
	var parts []string
	for _, c := range plan.ResourceChanges {
		noop := true
		for _, a := range c.Change.Actions {
			if a != "no-op" && a != "read" {
				noop = false
			}
		}
		if !noop {
			parts = append(parts, common.FormatChange(c))
		}
	}
	if len(parts) == 0 {
		return "(no parsed changes)"
	}
	return strings.Join(parts, "; ")
}

func idempotent(plan common.PlanResult) bool {
	for _, c := range plan.ResourceChanges {
		for _, a := range c.Change.Actions {
			if a != "no-op" && a != "read" {
				return false
			}
		}
	}
	return true
}

func validateOK(jsonOut string) bool {
	var res struct {
		Valid      bool `json:"valid"`
		ErrorCount int  `json:"error_count"`
	}
	if err := json.Unmarshal([]byte(jsonOut), &res); err != nil {
		return false
	}
	return res.Valid && res.ErrorCount == 0
}

func providerInstallBlocked(out string) bool {
	for _, n := range []string{
		"Failed to query available provider packages",
		"could not connect to registry", "failed to request discovery document",
		"403 Forbidden", "no such host", "i/o timeout", "dial tcp",
	} {
		if strings.Contains(out, n) {
			return true
		}
	}
	return false
}

func firstError(out string) string {
	// Prefer a terraform/json diagnostic summary; fall back to first "Error:" line.
	var j struct {
		Diagnostics []struct {
			Severity string `json:"severity"`
			Summary  string `json:"summary"`
			Detail   string `json:"detail"`
		} `json:"diagnostics"`
	}
	if json.Unmarshal([]byte(out), &j) == nil {
		for _, d := range j.Diagnostics {
			if d.Severity == "error" {
				s := d.Summary
				if d.Detail != "" {
					s += ": " + d.Detail
				}
				return clip(oneLine(s), 600)
			}
		}
	}
	// Plain-text terraform output: capture the "Error:" summary AND the
	// following diagnostic block (the `│`-prefixed detail / API message),
	// which is where the actionable cause lives — not just the summary.
	lines := strings.Split(out, "\n")
	for i, ln := range lines {
		if strings.Contains(ln, "Error:") {
			var block []string
			for _, bl := range lines[i:min(i+12, len(lines))] {
				if strings.Contains(bl, "╵") {
					break
				}
				t := strings.TrimSpace(strings.Trim(strings.TrimSpace(bl), "│╷╵"))
				if t != "" {
					block = append(block, t)
				}
			}
			return clip(oneLine(strings.Join(block, " ")), 600)
		}
	}
	return ""
}

// runUpdateStage implements the optional "update" stage. It is a no-op (stage
// stays "skip") unless MATRIX_UPDATE=1 AND scenarios/<name>/update.tfvars exists.
func runUpdateStage(t *testing.T, dir, name string, rc *ResourceCaps) {
	if os.Getenv("MATRIX_UPDATE") != "1" {
		return // gate unset → skip (default runs unaffected)
	}
	varFile := filepath.Join(dir, "update.tfvars")
	if _, err := os.Stat(varFile); err != nil {
		return // no update fixture for this scenario → skip
	}
	// Only meaningful once the resource is actually applied.
	if rc.Stages["apply"] != "ok" {
		return
	}

	if out, err := common.TFRun(t, dir, "apply", "-no-color", "-input=false", "-auto-approve", "-var-file=update.tfvars"); err != nil {
		rc.Stages["update"] = "fail"
		appendNote(rc, "update apply failed: "+firstError(out))
		return
	}
	// A clean re-plan WITH the same var-file proves the update converged
	// (no churn / non-idempotent in-place update).
	replan := common.PlanWithArgs(t, dir, "-var-file=update.tfvars")
	if idempotent(replan) {
		rc.Stages["update"] = "ok"
	} else {
		rc.Stages["update"] = "fail"
		appendNote(rc, "update non-idempotent: "+changedSummary(replan))
	}
}

// runImportStage implements the optional "import" stage. No-op (stays "skip")
// unless MATRIX_IMPORT=1. Runs `terraform import` in a throwaway copy of the
// scenario with its own empty state, so it never disturbs the live state that
// destroy still needs. A resource lacking ImportState records "unsupported".
func runImportStage(t *testing.T, dir, name string, rc *ResourceCaps) {
	if os.Getenv("MATRIX_IMPORT") != "1" {
		return // gate unset → skip
	}
	if rc.Stages["apply"] != "ok" {
		return
	}

	addr, id, err := primaryResourceAddrID(t, dir)
	if err != nil || addr == "" || id == "" {
		rc.Stages["import"] = "skip"
		appendNote(rc, "import: could not resolve primary resource addr/id: "+errStr(err))
		return
	}

	// Throwaway working dir: copy the scenario's *.tf so the resource block and
	// provider config exist, but keep a fresh empty state/backend so the import
	// target is the only thing in state. Runs in a temp dir under the OS tmp.
	work, derr := copyScenarioForImport(dir)
	if derr != nil {
		rc.Stages["import"] = "skip"
		appendNote(rc, "import: could not stage throwaway copy: "+derr.Error())
		return
	}
	defer os.RemoveAll(work)

	if out, ierr := common.TFRun(t, work, "init", "-backend=false", "-no-color", "-input=false"); ierr != nil {
		rc.Stages["import"] = "skip"
		appendNote(rc, "import: throwaway init failed: "+firstError(out))
		return
	}

	out, ierr := common.TFRun(t, work, "import", "-no-color", "-input=false", addr, id)
	if ierr != nil {
		if importUnsupported(out) {
			// Resource does not implement ImportState — this is the #4 gap, not a
			// failure of this run. Surface it without failing the stage.
			rc.Stages["import"] = "unsupported"
			appendNote(rc, "import unsupported (no ImportState; see #4): "+addr)
			return
		}
		rc.Stages["import"] = "fail"
		appendNote(rc, "import failed for "+addr+": "+firstError(out))
		return
	}
	rc.Stages["import"] = "ok"
}

// importUnsupported reports whether a terraform import error indicates the
// resource type does not implement ImportState (vs. a genuine import failure).
func importUnsupported(out string) bool {
	for _, sig := range []string{
		"resource import not implemented",
		"does not support import",
		"Import is not implemented",
		"doesn't support import",
		"Resource Import Not Implemented",
		"This resource does not support import",
	} {
		if strings.Contains(out, sig) {
			return true
		}
	}
	return false
}

// primaryResourceAddrID returns the address and id of the scenario's primary
// (first managed) resource, read from the live state via `terraform show -json`.
func primaryResourceAddrID(t *testing.T, dir string) (string, string, error) {
	showOut, err := common.TFRun(t, dir, "show", "-json")
	if err != nil {
		return "", "", err
	}
	var state struct {
		Values struct {
			RootModule struct {
				Resources []struct {
					Address string                     `json:"address"`
					Mode    string                     `json:"mode"`
					Values  map[string]json.RawMessage `json:"values"`
				} `json:"resources"`
			} `json:"root_module"`
		} `json:"values"`
	}
	if err := json.Unmarshal([]byte(showOut), &state); err != nil {
		return "", "", err
	}
	for _, r := range state.Values.RootModule.Resources {
		if r.Mode != "managed" {
			continue
		}
		var id string
		if raw, ok := r.Values["id"]; ok {
			_ = json.Unmarshal([]byte(raw), &id)
		}
		return r.Address, id, nil
	}
	return "", "", nil
}

// copyScenarioForImport makes a temp dir containing only the scenario's *.tf
// files (no state, no .terraform), suitable for a throwaway `terraform import`.
func copyScenarioForImport(dir string) (string, error) {
	work, err := os.MkdirTemp("", "matrix-import-")
	if err != nil {
		return "", err
	}
	files, _ := filepath.Glob(filepath.Join(dir, "*.tf"))
	for _, f := range files {
		b, rerr := os.ReadFile(f)
		if rerr != nil {
			os.RemoveAll(work)
			return "", rerr
		}
		if werr := os.WriteFile(filepath.Join(work, filepath.Base(f)), b, 0o644); werr != nil {
			os.RemoveAll(work)
			return "", werr
		}
	}
	return work, nil
}

// appendNote joins a new note onto rc.Note with a separator, preserving any
// earlier note (e.g. a replan non-idempotency) instead of overwriting it.
func appendNote(rc *ResourceCaps, s string) {
	if rc.Note == "" {
		rc.Note = s
		return
	}
	rc.Note += " | " + s
}

func errStr(err error) string {
	if err == nil {
		return ""
	}
	return err.Error()
}

// scenarioResource returns the first provider resource declared by a scenario.
func scenarioResource(name string) string {
	files, _ := filepath.Glob(filepath.Join(common.RepoRoot(), "scenarios", name, "*.tf"))
	for _, f := range files {
		b, err := os.ReadFile(f)
		if err != nil {
			continue
		}
		for _, m := range resourceDeclRe.FindAllStringSubmatch(string(b), -1) {
			return m[1]
		}
	}
	return ""
}
