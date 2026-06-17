#!/usr/bin/env python3
"""build_coverage.py - maintain a persistent per-resource coverage dashboard.

Merges a capability-matrix run (out/capability-matrix.json) into the persistent
coverage/coverage.json store, then regenerates COVERAGE.md (a funnel summary plus
a table grouped by service family).

The capability matrix walks each scenario through a fixed pipeline of stages:

    validate -> plan -> apply -> replan -> destroy

Each stage outcome is one of: ok | fail | blocked | skip | - . "blocked" is a
provider-init transient (see provider #38), NOT a resource defect; only "ok"
counts toward how far a resource has been *verified green*. The "highest_stage"
for a resource is the furthest stage in pipeline order that is "ok".

Usage:
    build_coverage.py [path/to/capability-matrix.json ...]

Idempotent: running it repeatedly with the same input(s) yields the same store.
"Most recent run wins": a record is only overwritten when the incoming run is
newer than (or equal-and-explicit to) what is already stored for that resource,
based on the run's timestamp (last_seen). Resources never seen are still listed
in the funnel denominator (the full provider surface) but carry no stages.

This script owns: coverage/coverage.json and COVERAGE.md. It reads the static
provider surface from coverage/provider_surface.json (generated from the
provider source by scripts/gen_ds_smoke.py), which splits the surface by kind:
87 managed resources (the funnel denominator) and 168 data sources. Data
sources are read-verified by the generated ds_<family> smoke scenarios; their
records land in the store under the scenario key and are fanned out to the
member data sources at render time.
"""

from __future__ import annotations

import datetime as _dt
import json
import os
import sys
from collections import OrderedDict

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
COV_DIR = os.path.join(REPO, "coverage")
COV_JSON = os.path.join(COV_DIR, "coverage.json")
SURFACE_JSON = os.path.join(COV_DIR, "provider_surface.json")
EXCLUDED_YAML = os.path.join(COV_DIR, "excluded_resources.yaml")
COV_MD = os.path.join(REPO, "COVERAGE.md")

STAGES = ["validate", "plan", "apply", "replan", "destroy"]
# Stage outcomes that count as "verified green".
OK = "ok"
PREFIX = "samsungcloudplatformv2_"


# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #
def load_json(path, default):
    if not os.path.exists(path):
        return default
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (json.JSONDecodeError, OSError):
        return default


def load_surface():
    """{"resources": {short_type: {family}}, "datasources": {short_type: {...}}}."""
    m = load_json(SURFACE_JSON, {})
    if not m:
        sys.stderr.write(
            "warn: %s missing/empty; family grouping and funnel totals "
            "will be incomplete\n" % SURFACE_JSON
        )
    return {"resources": m.get("resources", {}), "datasources": m.get("datasources", {})}


def load_excluded():
    """Curated map of resources excluded from the testable surface (reason ∈
    license / no-capacity / deprecated). Keyed by short resource name ->
    {reason, detail}. Split out of the testable funnel denominator and rendered
    in their own greyed section. YAML is parsed if PyYAML is available;
    missing/unparseable file -> {} (the dashboard then treats the full surface
    as testable, as before).
    """
    if not os.path.exists(EXCLUDED_YAML):
        return {}
    try:
        import yaml  # repo dependency (validate_registry.py, gen_scenarios.py)
        with open(EXCLUDED_YAML, encoding="utf-8") as fh:
            data = yaml.safe_load(fh) or {}
        return {k: v for k, v in data.items() if isinstance(v, dict)}
    except Exception as exc:  # pragma: no cover - defensive
        sys.stderr.write("warn: cannot read %s (%s); treating all resources as "
                         "testable\n" % (EXCLUDED_YAML, exc))
        return {}


def short_name(res):
    return res[len(PREFIX):] if res.startswith(PREFIX) else res


def ds_read_status(rec):
    """Collapse a smoke-scenario record into a read verdict for its members.

    Data sources are read at plan time (and re-read on apply), so plan==ok is
    the signal; validate/plan failures mean at least one member read is broken.
    """
    if not rec:
        return "untested"
    st = rec.get("stages", {})
    if st.get("plan") == OK:
        return OK
    if "fail" in (st.get("validate"), st.get("plan")):
        return "fail"
    if "blocked" in (st.get("validate"), st.get("plan"), st.get("apply")):
        return "blocked"
    return "untested"


def highest_stage(stages):
    """Furthest stage (in pipeline order) whose outcome is 'ok'; else None."""
    hi = None
    for s in STAGES:
        if stages.get(s) == OK:
            hi = s
    return hi


def normalize_stages(raw):
    """Coerce a run's stage map into the 5 canonical stages.

    Accepts the matrix glyph/text values; unknown/'-'/missing become 'skip'.
    """
    out = {}
    for s in STAGES:
        v = (raw or {}).get(s)
        if v in (None, "", "-"):
            v = "skip"
        out[s] = v
    # update/import are real (currently gated-off) matrix stages: keep them on
    # the dashboard axis as "skip" instead of stripping them (the columns
    # vanished from the published dashboard after the 2026-06-12 merge).
    for extra in ("update", "import"):
        v = (raw or {}).get(extra)
        out[extra] = "skip" if v in (None, "", "-") else v
    return out


def run_timestamp(run_url):
    """Best-effort: prefer an explicit timestamp; fall back to 'now' (UTC).

    Callers that have a real run time (e.g. the seed from issue comments) pass
    it in directly via merge_records(); for a live CI run the file has no
    timestamp, so we stamp it with the current time, which is monotonic per run.
    """
    return _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# --------------------------------------------------------------------------- #
# merge
# --------------------------------------------------------------------------- #
def merge_records(store, incoming):
    """Merge incoming records into store. Most-recent (by last_seen) wins.

    `incoming` is a list of dicts: {resource, stages, note, run_url, last_seen}.
    `store` is keyed by resource type. Returns the (mutated) store.
    """
    for rec in incoming:
        res = rec.get("resource")
        if not res:
            continue
        stages = normalize_stages(rec.get("stages"))
        seen = rec.get("last_seen") or run_timestamp(rec.get("run_url"))
        prev = store.get(res)
        # Most-recent wins: only overwrite when this run is not older.
        if prev and prev.get("last_seen", "") > seen:
            continue
        store[res] = {
            "stages": stages,
            "highest_stage": highest_stage(stages),
            "last_run_url": rec.get("run_url", ""),
            "last_seen": seen,
            "note": (rec.get("note") or "").strip(),
        }
    return store


# A scenario's matrix `resource` field is the FIRST resource block declared in
# its .tf (see scenarioResource() in tests/capability/matrix_test.go), which for
# self-contained scenarios is a PREREQUISITE, not the target — so we must NOT key
# the store by it. Instead derive the key from the scenario name (the same
# convention coverage.json uses): identity for the 82 canonically-named
# scenarios, these 4 aliases, ds_* kept as-is, import_smoke skipped.
SCENARIO_ALIASES = {
    "eventstreams_basic": "eventstreams_cluster",
    "loadbalancer_basic": "loadbalancer_loadbalancer",
    "security_group_basic": "security_group_security_group",
    "securitygroup_rule_basic": "security_group_security_group_rule",
}


def scenario_key(scenario):
    """Map a scenario name to its store key (resource type), or None to skip."""
    if not scenario:
        return None
    if scenario.startswith("ds_"):
        return scenario  # data-source smoke records are keyed by scenario name
    if scenario == "import_smoke":
        return None  # cross-cutting import test; no single primary resource
    return PREFIX + SCENARIO_ALIASES.get(scenario, scenario)


def records_from_matrix(path):
    """Read a capability-matrix.json run file into merge-ready records."""
    data = load_json(path, None)
    if data is None:
        sys.stderr.write("warn: cannot read matrix file %s; skipping\n" % path)
        return []
    if isinstance(data, dict):  # tolerate {"results": [...]} shapes
        data = data.get("results") or data.get("caps") or []
    run_url = os.environ.get("RUN_URL", "") or _ci_run_url()
    seen = run_timestamp(run_url)
    recs = []
    for c in data:
        # Key by scenario (robust); fall back to the matrix `resource` field only
        # when no scenario is present.
        res = scenario_key(c.get("scenario")) or c.get("resource")
        if not res:
            continue
        recs.append(
            {
                "resource": res,
                "stages": c.get("stages") or {},
                "note": c.get("note") or "",
                "run_url": run_url,
                "last_seen": seen,
            }
        )
    return recs


def _ci_run_url():
    server = os.environ.get("GITHUB_SERVER_URL", "https://github.com")
    repo = os.environ.get("GITHUB_REPOSITORY", "")
    rid = os.environ.get("GITHUB_RUN_ID", "")
    if repo and rid:
        return "%s/%s/actions/runs/%s" % (server, repo, rid)
    return ""


# --------------------------------------------------------------------------- #
# render
# --------------------------------------------------------------------------- #
def family_of(short, surface):
    info = surface["resources"].get(short) or surface["datasources"].get(short)
    if info:
        return info["family"]
    return short.split("_", 1)[0] or "(unknown)"


def build_markdown(store, surface, unprov=None):
    unprov = unprov or {}
    # Resource rows: provider surface resources plus any stray store record
    # that is neither a ds_* smoke scenario nor a known data source.
    all_types = set(surface["resources"])
    for k in store:
        if k.startswith("ds_"):
            continue
        all_types.add(short_name(k))
    all_types = sorted(all_types)
    surface_total = len(all_types)

    # Split out the platform-unprovisionable resources (license / no-capacity):
    # they are NOT defects and are excluded from the *testable* denominator, the
    # same way parent-arg-only data sources are. Tracked in their own section.
    unprov_types = [r for r in all_types if r in unprov]
    testable = [r for r in all_types if r not in unprov]
    total = len(testable)

    def rec_of(short):
        return store.get(PREFIX + short) or store.get(short)

    # Funnel: count testable resources reaching each stage as "ok".
    reach = {s: 0 for s in STAGES}
    # update/import are SEPARATE axes (not part of the lifecycle-green bar): the
    # in-place Update handler and ImportState. They are gated/optional in the
    # runner (MATRIX_UPDATE / MATRIX_IMPORT) and mostly "skip", so we surface
    # their coverage explicitly rather than fold them into the headline number.
    reach_update = 0
    reach_import = 0
    with_scenario = 0
    fully_green = 0
    for res in testable:
        rec = rec_of(res)
        if not rec:
            continue
        with_scenario += 1
        for s in STAGES:
            if rec["stages"].get(s) == OK:
                reach[s] += 1
        if rec["stages"].get("update") == OK:
            reach_update += 1
        if rec["stages"].get("import") == OK:
            reach_import += 1
        if all(rec["stages"].get(s) == OK for s in STAGES):
            fully_green += 1

    denom = total if total else 1
    pct = 100.0 * fully_green / denom

    out = []
    out.append("# Coverage Dashboard")
    out.append("")
    out.append(
        "Per-resource verification depth for the SCP Terraform provider, distilled "
        "from every \"Capability matrix outcome\" run. Each resource is walked "
        "through the pipeline `validate -> plan -> apply -> replan -> destroy`; "
        "a stage is **verified green** only when its outcome is `ok`. Data "
        "sources are tracked separately (see [Data sources](#data-sources)): "
        "standalone-readable ones are read-verified by the generated "
        "`ds_<family>` smoke scenarios; the rest require a parent-resource "
        "argument and are excluded from the testable denominator."
    )
    out.append("")
    out.append(
        "Legend: ok = verified green - fail = defect - blocked = provider-init "
        "transient (provider #38, not a resource defect) - skip = not exercised."
    )
    out.append("")
    out.append("_Generated by `scripts/build_coverage.py`. Do not edit by hand._")
    out.append("")

    # ----- funnel ----- #
    out.append("## Funnel")
    out.append("")
    out.append("| metric | count | of testable |")
    out.append("|---|---:|---:|")
    out.append(
        "| managed resources (provider surface) | %d | - |" % surface_total
    )
    out.append(
        "| excluded from testable surface (non-defect) | %d | - |"
        % len(unprov_types)
    )
    out.append("| **testable surface** | %d | 100%% |" % total)
    out.append(
        "| with a capability-matrix scenario run | %d | %d%% |"
        % (with_scenario, round(100.0 * with_scenario / denom))
    )
    for s in STAGES:
        out.append(
            "| reaching **%s** (green) | %d | %d%% |"
            % (s, reach[s], round(100.0 * reach[s] / denom))
        )
    out.append(
        "| **lifecycle green** (validate→plan→apply→replan→destroy ok) | %d | %.1f%% |"
        % (fully_green, pct)
    )
    out.append(
        "| in-place **update** verified (separate axis) | %d | %d%% |"
        % (reach_update, round(100.0 * reach_update / denom))
    )
    out.append(
        "| **import** verified (separate axis, ImportState #81) | %d | %d%% |"
        % (reach_import, round(100.0 * reach_import / denom))
    )
    out.append("")
    out.append(
        "> **\"lifecycle green\" is the create→replace→destroy lifecycle, NOT a full "
        "CRUD green.** Two axes are tracked separately and are still mostly "
        "unexercised: **update** (the in-place Update handler — gated by "
        "`MATRIX_UPDATE=1` and an `update.tfvars`; real defects live here, cf. "
        "provider #33/#71/#72) and **import** (`terraform import` / ImportState — "
        "gated by `MATRIX_IMPORT=1`; most resources don't implement it, #81). A "
        "resource can be lifecycle-green yet have a broken Update handler or no "
        "import support."
    )
    out.append("")

    # ----- per-family table ----- #
    by_family = OrderedDict()
    for res in testable:
        fam = family_of(res, surface)
        by_family.setdefault(fam, []).append(res)

    out.append("## By service family")
    out.append("")

    def cell(rec, stage):
        if not rec:
            return "-"
        return rec["stages"].get(stage, "skip")

    def clip(note):
        note = (note or "").replace("\n", " ").replace("|", "\\|")
        return note[:79] + "…" if len(note) > 80 else note

    for fam in sorted(by_family):
        members = sorted(by_family[fam])
        green = sum(
            1
            for r in members
            if rec_of(r)
            and all(rec_of(r)["stages"].get(s) == OK for s in STAGES)
        )
        out.append("### %s (%d/%d lifecycle green)" % (fam, green, len(members)))
        out.append("")
        out.append(
            "| resource | validate | plan | apply | replan | destroy | "
            "highest | note |"
        )
        out.append("|---|---|---|---|---|---|---|---|")
        for r in members:
            rec = rec_of(r)
            hi = rec["highest_stage"] if rec else None
            out.append(
                "| `%s` | %s | %s | %s | %s | %s | %s | %s |"
                % (
                    r,
                    cell(rec, "validate"),
                    cell(rec, "plan"),
                    cell(rec, "apply"),
                    cell(rec, "replan"),
                    cell(rec, "destroy"),
                    hi or "-",
                    clip(rec["note"] if rec else ""),
                )
            )
        out.append("")

    # ----- platform-unprovisionable resources ----- #
    if unprov_types:
        out.append("## Excluded resources (not in testable surface)")
        out.append("")
        out.append(
            "Resources excluded from the testable funnel denominator — **not** "
            "provider/fixture defects. Reasons: vendor **license** not held, "
            "physical / entitlement / **capacity** the account lacks, a "
            "**deprecated** service being retired, a real **cost** commitment, or "
            "intentionally **out-of-scope**. Split out the same way parent-arg-only "
            "data sources are, so \"100% coverage\" means 100% of what is actually "
            "testable. Curated in `coverage/excluded_resources.yaml`."
        )
        out.append("")
        out.append("| resource | family | reason | detail |")
        out.append("|---|---|---|---|")
        for r in sorted(unprov_types):
            meta = unprov.get(r, {})
            out.append(
                "| `%s` | %s | %s | %s |"
                % (
                    r,
                    family_of(r, surface),
                    meta.get("reason", "-"),
                    clip(meta.get("detail", "")),
                )
            )
        out.append("")

    # ----- data sources ----- #
    ds = surface["datasources"]
    smoke = {t: e for t, e in ds.items() if e.get("scenario")}
    excluded = {t: e for t, e in ds.items() if e.get("excluded")}
    read_ok = sum(
        1 for t, e in smoke.items() if ds_read_status(store.get(e["scenario"])) == OK
    )
    read_fail = sum(
        1
        for t, e in smoke.items()
        if ds_read_status(store.get(e["scenario"])) == "fail"
    )
    out.append("## Data sources")
    out.append("")
    out.append(
        "Read-only verification: each `ds_<family>` smoke scenario reads every "
        "standalone-readable data source of that family (list endpoints with "
        "optional/constant-only arguments) through the same "
        "validate/plan/apply pipeline; a data source is **read-verified** when "
        "its scenario's plan is green. Data sources requiring a parent-resource "
        "argument (id etc.) are excluded - they are exercised implicitly by "
        "resource scenarios, not testable standalone."
    )
    out.append("")
    out.append("| metric | count |")
    out.append("|---|---:|")
    out.append("| total data sources | %d |" % len(ds))
    out.append("| standalone-readable (smoke-covered) | %d |" % len(smoke))
    out.append("| **read-verified green** | %d |" % read_ok)
    out.append("| read failing | %d |" % read_fail)
    out.append("| excluded (requires parent-resource arg) | %d |" % len(excluded))
    out.append("")
    out.append("| data source | family | read | note |")
    out.append("|---|---|---|---|")
    for t in sorted(ds):
        e = ds[t]
        if e.get("excluded"):
            status, note = "excluded", e.get("reason", "")
        else:
            rec = store.get(e["scenario"])
            status = ds_read_status(rec)
            note = "via `%s`" % e["scenario"]
            if rec and status != OK and rec.get("note"):
                note += " - " + rec["note"]
        out.append(
            "| `%s` | %s | %s | %s |" % (t, e["family"], status, clip(note))
        )
    out.append("")

    return "\n".join(out) + "\n"


# --------------------------------------------------------------------------- #
# main
# --------------------------------------------------------------------------- #
def main(argv):
    surface = load_surface()
    unprov = load_excluded()

    store = load_json(COV_JSON, {})
    if not isinstance(store, dict):
        store = {}

    for path in argv:
        recs = records_from_matrix(path)
        merge_records(store, recs)

    # Recompute highest_stage for every record (idempotent / self-healing).
    for res, rec in store.items():
        rec["stages"] = normalize_stages(rec.get("stages"))
        rec["highest_stage"] = highest_stage(rec["stages"])

    os.makedirs(COV_DIR, exist_ok=True)
    ordered = OrderedDict(sorted(store.items()))
    with open(COV_JSON, "w", encoding="utf-8") as fh:
        json.dump(ordered, fh, indent=2, sort_keys=True)
        fh.write("\n")

    md = build_markdown(store, surface, unprov)
    with open(COV_MD, "w", encoding="utf-8") as fh:
        fh.write(md)

    # Brief stdout summary for CI logs. Count only managed-resource records
    # (ds_* smoke-scenario records are summarized in the Data sources section).
    res_recs = [
        r
        for k, r in store.items()
        if not short_name(k).startswith("ds_") and not k.startswith("ds_")
    ]
    green = sum(
        1 for r in res_recs if all(r["stages"].get(s) == OK for s in STAGES)
    )
    sys.stderr.write(
        "coverage: %d resource records, %d lifecycle green; wrote %s + %s\n"
        % (len(res_recs), green, COV_JSON, COV_MD)
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
