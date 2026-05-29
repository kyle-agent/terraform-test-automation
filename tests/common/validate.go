package common

// validate.go adds a dry-run-safe schema check: `terraform validate` runs the
// config against the *provider schema* without contacting the cloud or needing
// credentials. It is the primary signal that catches schema regressions (an
// attribute renamed/removed, a type changed) the moment a new provider version
// is released — exactly the class of breakage the dry-run gate exists for.

import (
	"encoding/json"
	"os/exec"
	"testing"
)

// TerraformAvailable reports whether a terraform binary is on PATH.
func TerraformAvailable() bool {
	_, err := exec.LookPath("terraform")
	return err == nil
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
// match the provider schema. It skips (does not fail) when terraform is not
// installed, so `make test` stays usable on machines without the CLI while CI
// — which always installs terraform — gets full schema coverage.
func Validate(t *testing.T, dir string) {
	t.Helper()
	if !TerraformAvailable() {
		t.Skip("terraform not installed; schema validate skipped (CI installs it)")
	}
	if out, err := TFRun(t, dir, "init", "-backend=false", "-no-color", "-input=false"); err != nil {
		t.Fatalf("terraform init failed in %s: %v\n%s", dir, err, out)
	}
	out, _ := TFRun(t, dir, "validate", "-no-color", "-json")
	var res validateJSON
	if err := json.Unmarshal([]byte(out), &res); err != nil {
		t.Fatalf("could not parse `terraform validate -json` output in %s: %v\n%s", dir, err, out)
	}
	if !res.Valid || res.ErrorCount > 0 {
		t.Fatalf("terraform validate reported %d error(s) in %s:\n%s", res.ErrorCount, dir, out)
	}
}
