package common

// discovery.go holds the "dynamic" primitives: instead of hard-coding which
// resources / scenarios exist, we discover them at run time from
//   - config/scp_resources.json  (the provider's real resource surface), and
//   - scenarios/*/*.tf           (the fixtures this repo actually exercises).
//
// This lets the regression suite track coverage drift automatically: when the
// provider grows a new resource (registry sync) or a scenario is added/removed,
// the coverage report and the dynamic CI matrix move with it — no manual edits.

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
	"strings"
)

// RepoRoot returns the absolute path to the repository root. It is resolved
// from this source file's compile-time location (tests/common/discovery.go),
// which is robust regardless of the test's working directory. A cwd walk-up to
// go.mod is used as a fallback.
func RepoRoot() string {
	if _, file, _, ok := runtime.Caller(0); ok {
		// file == <root>/tests/common/discovery.go
		root := filepath.Dir(filepath.Dir(filepath.Dir(file)))
		if _, err := os.Stat(filepath.Join(root, "go.mod")); err == nil {
			return root
		}
	}
	dir, err := os.Getwd()
	if err != nil {
		return "."
	}
	for i := 0; i < 8; i++ {
		if _, err := os.Stat(filepath.Join(dir, "go.mod")); err == nil {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	return dir
}

// ResourceCatalog mirrors config/scp_resources.json.
type ResourceCatalog struct {
	Provider struct {
		Source            string   `json:"source"`
		Registry          string   `json:"registry"`
		LatestVersionSeen string   `json:"latest_version_seen"`
		CatalogSyncedAt   string   `json:"catalog_synced_at"`
		AuthEnv           []string `json:"auth_env"`
	} `json:"provider"`
	Resources []string `json:"resources"`
}

// LoadResourceCatalog reads config/scp_resources.json from the repo root.
func LoadResourceCatalog() (ResourceCatalog, error) {
	var c ResourceCatalog
	b, err := os.ReadFile(filepath.Join(RepoRoot(), "config", "scp_resources.json"))
	if err != nil {
		return c, err
	}
	if err := json.Unmarshal(b, &c); err != nil {
		return c, err
	}
	sort.Strings(c.Resources)
	return c, nil
}

// ListScenarioDirs returns the names of every scenario directory under
// scenarios/ (i.e. those that contain at least one .tf file).
func ListScenarioDirs() ([]string, error) {
	base := filepath.Join(RepoRoot(), "scenarios")
	entries, err := os.ReadDir(base)
	if err != nil {
		return nil, err
	}
	var out []string
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		matches, _ := filepath.Glob(filepath.Join(base, e.Name(), "*.tf"))
		if len(matches) > 0 {
			out = append(out, e.Name())
		}
	}
	sort.Strings(out)
	return out, nil
}

var resourceDeclRe = regexp.MustCompile(`(?m)^\s*resource\s+"(samsungcloudplatformv2_[a-z0-9_]+)"`)

// validateOptOutMarker, when present in any of a scenario's .tf files, tells
// the schema-validate sweep to skip that scenario. Used for intentionally
// partial fixtures (e.g. an empty resource block whose required arguments are
// filled by the integration variant via TF_VAR_* / imported state), which
// would otherwise fail `terraform validate` with "Missing required argument".
const validateOptOutMarker = "regr:no-validate"

// ScenarioOptsOutOfValidate reports whether the named scenario carries the
// opt-out marker in any of its .tf files.
func ScenarioOptsOutOfValidate(name string) bool {
	files, _ := filepath.Glob(filepath.Join(RepoRoot(), "scenarios", name, "*.tf"))
	for _, f := range files {
		if b, err := os.ReadFile(f); err == nil && strings.Contains(string(b), validateOptOutMarker) {
			return true
		}
	}
	return false
}

// ScanScenarioResources walks every scenario .tf file and returns the set of
// provider resource types that are actually declared, deduplicated and sorted.
func ScanScenarioResources() ([]string, error) {
	dirs, err := ListScenarioDirs()
	if err != nil {
		return nil, err
	}
	seen := map[string]struct{}{}
	for _, d := range dirs {
		files, _ := filepath.Glob(filepath.Join(RepoRoot(), "scenarios", d, "*.tf"))
		for _, f := range files {
			b, err := os.ReadFile(f)
			if err != nil {
				continue
			}
			for _, m := range resourceDeclRe.FindAllStringSubmatch(string(b), -1) {
				seen[m[1]] = struct{}{}
			}
		}
	}
	out := make([]string, 0, len(seen))
	for r := range seen {
		out = append(out, r)
	}
	sort.Strings(out)
	return out, nil
}

// Coverage is the result of intersecting the provider's resource surface with
// the resources that the scenarios under scenarios/ actually exercise.
type Coverage struct {
	Total     int      `json:"total_resources"`
	Covered   []string `json:"covered"`
	Uncovered []string `json:"uncovered"`
	// Unknown lists resources referenced by scenarios but NOT present in the
	// catalog — usually a typo or a resource the catalog needs to be synced for.
	Unknown []string `json:"unknown"`
	Percent float64  `json:"percent"`
}

// ComputeCoverage compares the catalog against what the scenarios declare.
func ComputeCoverage(cat ResourceCatalog, scenarioResources []string) Coverage {
	known := map[string]bool{}
	for _, r := range cat.Resources {
		known[r] = true
	}
	declared := map[string]bool{}
	for _, r := range scenarioResources {
		declared[r] = true
	}

	var cov Coverage
	cov.Total = len(cat.Resources)
	for _, r := range cat.Resources {
		if declared[r] {
			cov.Covered = append(cov.Covered, r)
		} else {
			cov.Uncovered = append(cov.Uncovered, r)
		}
	}
	for _, r := range scenarioResources {
		if !known[r] {
			cov.Unknown = append(cov.Unknown, r)
		}
	}
	sort.Strings(cov.Covered)
	sort.Strings(cov.Uncovered)
	sort.Strings(cov.Unknown)
	if cov.Total > 0 {
		cov.Percent = float64(len(cov.Covered)) / float64(cov.Total) * 100
	}
	return cov
}

// WriteCoverageReport persists the coverage result as JSON and a small Markdown
// table under OUTPUT_DIR (default "out"), returning the markdown path.
func WriteCoverageReport(cov Coverage, cat ResourceCatalog) (string, error) {
	dir := os.Getenv("OUTPUT_DIR")
	if dir == "" {
		dir = filepath.Join(RepoRoot(), "out")
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}

	if b, err := json.MarshalIndent(cov, "", "  "); err == nil {
		_ = os.WriteFile(filepath.Join(dir, "coverage.json"), b, 0o644)
	}

	var sb strings.Builder
	sb.WriteString("# Regression Coverage\n\n")
	sb.WriteString("Provider: `" + cat.Provider.Source + "` (catalog v" + cat.Provider.LatestVersionSeen + ")\n\n")
	sb.WriteString("Covered " +
		itoa(len(cov.Covered)) + " / " + itoa(cov.Total) +
		" resources (" + ftoa1(cov.Percent) + "%).\n\n")
	if len(cov.Covered) > 0 {
		sb.WriteString("## Covered\n")
		for _, r := range cov.Covered {
			sb.WriteString("- `" + r + "`\n")
		}
		sb.WriteString("\n")
	}
	if len(cov.Unknown) > 0 {
		sb.WriteString("## Unknown (scenario references not in catalog — sync needed)\n")
		for _, r := range cov.Unknown {
			sb.WriteString("- `" + r + "`\n")
		}
		sb.WriteString("\n")
	}
	sb.WriteString("## Uncovered (" + itoa(len(cov.Uncovered)) + ")\n")
	for _, r := range cov.Uncovered {
		sb.WriteString("- `" + r + "`\n")
	}
	mdPath := filepath.Join(dir, "coverage.md")
	if err := os.WriteFile(mdPath, []byte(sb.String()), 0o644); err != nil {
		return "", err
	}
	return mdPath, nil
}

// small dependency-free formatting helpers (avoid importing fmt/strconv churn
// in a file that is mostly string assembly).
func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var buf [20]byte
	i := len(buf)
	for n > 0 {
		i--
		buf[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		buf[i] = '-'
	}
	return string(buf[i:])
}

func ftoa1(f float64) string {
	whole := int(f)
	frac := int((f-float64(whole))*10 + 0.5)
	if frac >= 10 {
		whole++
		frac = 0
	}
	return itoa(whole) + "." + itoa(frac)
}
