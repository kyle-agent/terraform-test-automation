package common

// validate.go adds a dry-run-safe schema check: `terraform validate` runs the
// config against the *provider schema* without contacting the cloud or needing
// credentials. It is the primary signal that catches schema regressions (an
// attribute renamed/removed, a type changed) the moment a new provider version
// is released — exactly the class of breakage the dry-run gate exists for.

import (
	"encoding/json"
	"os/exec"
	"strings"
	"testing"
)

// TerraformAvailable reports whether a terraform binary is on PATH.
func TerraformAvailable() bool {
	_, err := exec.LookPath("terraform")
	return err == nil
}

// providerInstallFailure reports whether terraform init output indicates the
// provider could not be *installed* (registry blocked, network down, no
// matching version) — an environment limitation, not a config regression.
// In locked-down networks registry.terraform.io is unreachable (e.g. 403), so
// we must not turn that into a red regression gate.
func providerInstallFailure(out string) bool {
	needles := []string{
		"Failed to query available provider packages",
		"could not connect to registry",
		"Failed to install provider",
		"failed to request discovery document",
		"403 Forbidden",
		"no available releases match",
		"registry service is unreachable",
		"context deadline exceeded",
		"i/o timeout",
		"dial tcp",
		"no such host",
	}
	for _, n := range needles {
		if strings.Contains(out, n) {
			return true
		}
	}
	return false
}

// validateJSON mirrors the relevant subset of `terraform validate -json`.
type validateJSON struct {
	Valid        bool         `json:"valid"`
	ErrorCount   int          `json:"error_count"`
	WarningCount int          `json:"warning_count"`
	Diagnostics  []Diagnostic `json:"diagnostics"`
}

// Validate runs `terraform init -backend=false` + `terraform validate -json`
// in the given scenario directory and fails the test if the config does not
// match the provider schema.
//
// It SKIPS (does not fail) in two cases that are environmental rather than
// regressions:
//   - terraform is not installed, or
//   - the provider cannot be installed (registry blocked / offline).
//
// This keeps the dry-run gate green in locked-down CI (where the Terraform
// registry is unreachable) while still catching real schema regressions in any
// environment that can install the provider (registry access or a configured
// provider mirror / TF_CLI_CONFIG_FILE).
func Validate(t *testing.T, dir string) {
	t.Helper()
	if !TerraformAvailable() {
		t.Skip("terraform not installed; schema validate skipped (CI installs it)")
	}
	out, err := TFRun(t, dir, "init", "-backend=false", "-no-color", "-input=false")
	if err != nil {
		if providerInstallFailure(out) {
			t.Skipf("provider not installable in this environment (registry blocked/offline); schema validate skipped:\n%s", lastLines(out, 3))
		}
		t.Fatalf("terraform init failed in %s: %v\n%s", dir, err, out)
	}
	out, _ = TFRun(t, dir, "validate", "-no-color", "-json")
	var res validateJSON
	if err := json.Unmarshal([]byte(out), &res); err != nil {
		t.Fatalf("could not parse `terraform validate -json` output in %s: %v\n%s", dir, err, out)
	}
	if !res.Valid || res.ErrorCount > 0 {
		t.Fatalf("terraform validate reported %d error(s) in %s:\n%s", res.ErrorCount, dir, out)
	}
}

// lastLines returns the final n non-empty lines of s, for compact skip logs.
func lastLines(s string, n int) string {
	lines := strings.Split(strings.TrimSpace(s), "\n")
	if len(lines) > n {
		lines = lines[len(lines)-n:]
	}
	return strings.Join(lines, "\n")
}
