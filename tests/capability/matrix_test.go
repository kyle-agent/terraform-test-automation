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
		rc.Stages["plan"] = "fail"
		rc.Note = firstError(plan.RawOutput)
		return rc
	}
	rc.Stages["plan"] = "ok"

	out, err := common.TFRun(t, dir, "apply", "-no-color", "-input=false", "-auto-approve")
	if err != nil {
		rc.Stages["apply"] = "fail"
		rc.Note = firstError(out)
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
				return clip(oneLine(s), 160)
			}
		}
	}
	for _, ln := range strings.Split(out, "\n") {
		if strings.Contains(ln, "Error:") {
			return clip(oneLine(strings.TrimSpace(ln)), 160)
		}
	}
	return ""
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
