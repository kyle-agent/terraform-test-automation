package common

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"
)

// Result is a single regression test outcome, suitable for JSON serialization
// and consumption by the issue-reporter script.
type Result struct {
	TestName   string    `json:"test"`
	Chapter    string    `json:"chapter"`
	IssueRef   string    `json:"issue_ref"`        // e.g. "kyle-agent/terraform-provider-samsungcloudplatformv2#11 (1-D)"
	Severity   string    `json:"severity"`         // critical / high / medium
	Status     string    `json:"status"`           // pass / fail / skip
	Mode       string    `json:"mode"`             // dry-run / integration
	StartedAt  time.Time `json:"started_at"`
	DurationMs int64     `json:"duration_ms"`
	Summary    string    `json:"summary"`
	Details    string    `json:"details,omitempty"`
}

var (
	resultMu sync.Mutex
	results  []Result
)

// RecordResult appends a result to the in-memory buffer and writes the
// running JSON file after each call so partial runs are not lost.
func RecordResult(r Result) {
	resultMu.Lock()
	defer resultMu.Unlock()
	results = append(results, r)
	_ = flushResults()
}

func flushResults() error {
	dir := os.Getenv("OUTPUT_DIR")
	if dir == "" {
		dir = "out"
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	f, err := os.Create(filepath.Join(dir, "results.json"))
	if err != nil {
		return err
	}
	defer f.Close()
	enc := json.NewEncoder(f)
	enc.SetIndent("", "  ")
	return enc.Encode(results)
}

// CaseMeta is metadata for a single regression test. Defined once next to the
// test function and passed to RecordResult so reports stay self-describing.
type CaseMeta struct {
	Name     string
	Chapter  string
	IssueRef string
	Severity string
	Summary  string
}

// Wrap is a tiny convenience to record pass/fail timing without boilerplate.
//
//	defer common.Wrap(t, common.CaseMeta{
//	    Name: t.Name(), Chapter: "chapter1_core",
//	    IssueRef: "#11 (2-A)", Severity: "critical",
//	    Summary: "id RequiresReplace causes destroy+create on re-apply",
//	})()
func Wrap(t interface {
	Name() string
	Failed() bool
	Skipped() bool
}, m CaseMeta) func() {
	start := time.Now()
	return func() {
		status := "pass"
		switch {
		case t.Failed():
			status = "fail"
		case t.Skipped():
			status = "skip"
		}
		RecordResult(Result{
			TestName:   m.Name,
			Chapter:    m.Chapter,
			IssueRef:   m.IssueRef,
			Severity:   m.Severity,
			Status:     status,
			Mode:       Mode(),
			StartedAt:  start,
			DurationMs: time.Since(start).Milliseconds(),
			Summary:    m.Summary,
		})
	}
}

// SummaryLine returns a human-readable one-liner for log tail. Useful for CI
// to spot failures in a giant log.
func SummaryLine(r Result) string {
	return fmt.Sprintf("[%s] %s | %s | %s | %dms | %s",
		r.Status, r.Severity, r.Chapter, r.TestName, r.DurationMs, r.Summary)
}
