package capability

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/kyle-agent/terraform-test-automation/tests/common"
)

var resourceDeclRe = regexp.MustCompile(`(?m)^\s*resource\s+"(samsungcloudplatformv2_[a-z0-9_]+)"`)

// stageNames is the fixed pipeline, in order.
//
// "update" and "import" are OPTIONAL extra stages, gated by MATRIX_UPDATE=1 and
// MATRIX_IMPORT=1 respectively. When their env gate is unset they always record
// "skip", so default runs are byte-for-byte unaffected. They are placed after
// "replan" (both run while the applied resource still exists) and before
// "destroy" so the table reads in execution order.
// "destroy_verify" (OPTIONAL, gated by DESTROY_VERIFY=1) runs after destroy and
// confirms via the Open API that the created resources are actually gone (404) —
// catching "destroy reported success but the resource lingers" (cf. provider
// #77/#82). It records ok|leak|skip and, like update/import, stays "skip" when the
// gate is unset so default runs are unaffected.
var stageNames = []string{"validate", "plan", "apply", "replan", "update", "import", "destroy", "destroy_verify"}

// ResourceCaps captures the per-stage outcome for one scenario.
type ResourceCaps struct {
	Scenario string            `json:"scenario"`
	Resource string            `json:"resource"`
	Stages   map[string]string `json:"stages"` // stage -> ok|fail|skip
	Note     string            `json:"note,omitempty"`
}

// glyph renders a stage outcome as a compact cell.
func glyph(state string) string {
	switch state {
	case "ok":
		return "✅"
	case "fail":
		return "❌"
	case "blocked":
		return "🚧" // provider-init transient (e.g. #38) — not a resource defect
	case "unsupported":
		return "🚫" // capability not implemented (e.g. no ImportState, see #4)
	default:
		return "⊘" // skip / not exercised
	}
}

func outDir() string {
	if d := os.Getenv("OUTPUT_DIR"); d != "" {
		return d
	}
	return filepath.Join(common.RepoRoot(), "out")
}

// writeMatrix persists the capability matrix as JSON and Markdown.
func writeMatrix(caps []ResourceCaps) error {
	dir := outDir()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}

	if b, err := json.MarshalIndent(caps, "", "  "); err == nil {
		_ = os.WriteFile(filepath.Join(dir, "capability-matrix.json"), b, 0o644)
	}

	// Per-stage tally.
	tally := map[string]map[string]int{}
	for _, s := range stageNames {
		tally[s] = map[string]int{"ok": 0, "fail": 0, "skip": 0}
	}
	for _, c := range caps {
		for _, s := range stageNames {
			tally[s][c.Stages[s]]++
		}
	}

	var sb strings.Builder
	sb.WriteString("# Capability Matrix\n\n")
	sb.WriteString("General view of what works / what doesn't across every scenario, by stage.\n")
	sb.WriteString("Mode: `" + common.Mode() + "`. Legend: ✅ ok · ❌ fail · 🚫 unsupported · 🚧 blocked · ⊘ not exercised.\n")
	sb.WriteString("`update`/`import` are optional stages (gated by MATRIX_UPDATE / MATRIX_IMPORT); ⊘ when off.\n\n")

	sb.WriteString("## Per-stage summary\n\n")
	sb.WriteString("| stage | ✅ ok | ❌ fail | ⊘ skip |\n|---|---|---|---|\n")
	for _, s := range stageNames {
		sb.WriteString("| " + s + " | " +
			itoa(tally[s]["ok"]) + " | " +
			itoa(tally[s]["fail"]) + " | " +
			itoa(tally[s]["skip"]) + " |\n")
	}
	sb.WriteString("\n")

	// Failures first — the actionable list.
	var failing []ResourceCaps
	for _, c := range caps {
		for _, s := range stageNames {
			if c.Stages[s] == "fail" {
				failing = append(failing, c)
				break
			}
		}
	}
	if len(failing) > 0 {
		sb.WriteString("## ❌ Failing (drill into these)\n\n")
		sb.WriteString("| resource | first failing stage | note |\n|---|---|---|\n")
		for _, c := range failing {
			stage := ""
			for _, s := range stageNames {
				if c.Stages[s] == "fail" {
					stage = s
					break
				}
			}
			sb.WriteString("| `" + c.Resource + "` | " + stage + " | " +
				escapePipes(c.Note) + " |\n")
		}
		sb.WriteString("\n")
	}

	// Full matrix.
	sb.WriteString("## Full matrix\n\n")
	sb.WriteString("| resource |")
	for _, s := range stageNames {
		sb.WriteString(" " + s + " |")
	}
	sb.WriteString("\n|---|" + strings.Repeat("---|", len(stageNames)) + "\n")
	for _, c := range caps {
		name := c.Resource
		if name == "" {
			name = c.Scenario
		}
		sb.WriteString("| `" + name + "` |")
		for _, s := range stageNames {
			sb.WriteString(" " + glyph(c.Stages[s]) + " |")
		}
		sb.WriteString("\n")
	}

	return os.WriteFile(filepath.Join(dir, "capability-matrix.md"), []byte(sb.String()), 0o644)
}

func escapePipes(s string) string { return strings.ReplaceAll(oneLine(s), "|", "\\|") }

func oneLine(s string) string { return strings.Join(strings.Fields(s), " ") }
func clip(s string, n int) string {
	if len(s) > n {
		return s[:n] + "…"
	}
	return s
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var b [20]byte
	i := len(b)
	for n > 0 {
		i--
		b[i] = byte('0' + n%10)
		n /= 10
	}
	return string(b[i:])
}
