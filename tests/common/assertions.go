package common

import (
	"fmt"
	"strings"
	"testing"
)

// ChangedSummary returns a concise, log-free description of every non-noop
// resource change in a plan (address + actions), suitable for storing in the
// structured result so a failure is diagnosable without the full CI log.
func ChangedSummary(plan PlanResult) string {
	var parts []string
	for _, c := range plan.ResourceChanges {
		noop := true
		for _, a := range c.Change.Actions {
			if a != "no-op" && a != "read" {
				noop = false
			}
		}
		if !noop {
			parts = append(parts, FormatActions(c))
		}
	}
	if len(parts) == 0 {
		return "no resource_changes parsed (see raw output)"
	}
	return strings.Join(parts, "; ")
}

// AssertNoChanges fails the test if the plan contains any non-noop changes.
// This is the canonical assertion for "re-apply with no config changes should
// produce a clean plan" regressions (e.g. Chapter 1 #2, Chapter 4 #14).
func AssertNoChanges(t *testing.T, plan PlanResult) {
	t.Helper()
	for _, c := range plan.ResourceChanges {
		for _, a := range c.Change.Actions {
			if a != "no-op" && a != "read" {
				AttachDetail(t.Name(), "unexpected plan change: "+ChangedSummary(plan))
				t.Fatalf("expected no changes but got %s\nfull plan:\n%s",
					FormatActions(c), plan.RawOutput)
			}
		}
	}
}

// AssertReplacementCount asserts that the plan contains exactly `want`
// destroy-then-create entries. Used to verify that a fix prevents
// unintended replacements (e.g. id RequiresReplace bug).
func AssertReplacementCount(t *testing.T, plan PlanResult, want int) {
	t.Helper()
	got := 0
	for _, c := range plan.ResourceChanges {
		if isReplace(c.Change.Actions) {
			got++
		}
	}
	if got != want {
		AttachDetail(t.Name(), fmt.Sprintf("replacement count got %d want %d: %s",
			got, want, ChangedSummary(plan)))
		t.Fatalf("replacement count: got %d, want %d\nplan:\n%s",
			got, want, plan.RawOutput)
	}
}

// AssertNoReplacement is shorthand for AssertReplacementCount(plan, 0).
func AssertNoReplacement(t *testing.T, plan PlanResult) {
	t.Helper()
	AssertReplacementCount(t, plan, 0)
}

// AssertOutputContains fails if `needle` is not in the raw plan/apply output.
// Useful for verifying specific error messages (e.g. "Failed to get endpoint
// list" should *not* appear in normal runs).
func AssertOutputContains(t *testing.T, output, needle string) {
	t.Helper()
	if !strings.Contains(output, needle) {
		t.Fatalf("output does not contain %q\nfull output:\n%s", needle, output)
	}
}

// AssertOutputAbsent fails if `needle` IS in the output.
func AssertOutputAbsent(t *testing.T, output, needle string) {
	t.Helper()
	if strings.Contains(output, needle) {
		t.Fatalf("output unexpectedly contains %q\nfull output:\n%s", needle, output)
	}
}

// AssertNoPanic looks for go panic signatures in the output.
// Used after running a scenario that historically crashed the provider
// (e.g. securitygrouprule.go Update panic, slice [0] crashes).
func AssertNoPanic(t *testing.T, output string) {
	t.Helper()
	signatures := []string{
		"panic: ",
		"runtime error: index out of range",
		"runtime error: invalid memory address",
		"goroutine 1 [running]:",
	}
	for _, s := range signatures {
		if strings.Contains(output, s) {
			t.Fatalf("provider panic detected (%s)\nfull output:\n%s", s, output)
		}
	}
}

// AssertDiagnosticAbsent fails if any diagnostic with the given severity
// contains the given substring. Useful for "we should no longer see Service
// Check Failed List" type assertions.
func AssertDiagnosticAbsent(t *testing.T, output, severity, needle string) {
	t.Helper()
	sevTag := fmt.Sprintf("│ %s:", capitalize(severity))
	lines := strings.Split(output, "\n")
	for i, ln := range lines {
		if strings.Contains(ln, sevTag) {
			block := strings.Join(lines[i:min(i+10, len(lines))], "\n")
			if strings.Contains(block, needle) {
				t.Fatalf("expected diagnostic absent but found %q under %s:\n%s",
					needle, severity, block)
			}
		}
	}
}

func isReplace(actions []string) bool {
	if len(actions) != 2 {
		return false
	}
	hasDelete, hasCreate := false, false
	for _, a := range actions {
		if a == "delete" {
			hasDelete = true
		}
		if a == "create" {
			hasCreate = true
		}
	}
	return hasDelete && hasCreate
}

func capitalize(s string) string {
	if s == "" {
		return s
	}
	return strings.ToUpper(s[:1]) + s[1:]
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
