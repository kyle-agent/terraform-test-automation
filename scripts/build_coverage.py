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
resource->family map from coverage/resource_families.json (generated from the
provider source; the authoritative list of ~191 resource types).
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
FAMILIES_JSON = os.path.join(COV_DIR, "resource_families.json")
COV_MD = os.path.join(REPO, "COVERAGE.md")

STAGES = ["validate", "plan", "apply", "replan", "destroy"]
# Stage outcomes that count as "verified green".
OK = "ok"


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


def load_families():
    """resource_type -> service family. The full provider surface lives here."""
    m = load_json(FAMILIES_JSON, {})
    if not m:
        sys.stderr.write(
            "warn: %s missing/empty; family grouping and funnel totals "
            "will be incomplete\n" % FAMILIES_JSON
        )
    return m


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
        res = c.get("resource") or c.get("scenario")
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
def family_of(resource, families):
    if resource in families:
        return families[resource]
    # Fall back to the leading segment after the provider prefix.
    base = resource
    pfx = "samsungcloudplatformv2_"
    if base.startswith(pfx):
        base = base[len(pfx):]
    return base.split("_", 1)[0] or "(unknown)"


def build_markdown(store, families):
    total = len(families) if families else len(store)
    all_types = sorted(set(families) | set(store))
    if families:
        total = len(set(families))

    # Funnel: count resources reaching each stage as "ok".
    reach = {s: 0 for s in STAGES}
    with_scenario = 0
    fully_green = 0
    for res in all_types:
        rec = store.get(res)
        if not rec:
            continue
        with_scenario += 1
        for s in STAGES:
            if rec["stages"].get(s) == OK:
                reach[s] += 1
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
        "a stage is **verified green** only when its outcome is `ok`."
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
    out.append("| metric | count | of total |")
    out.append("|---|---:|---:|")
    out.append("| total provider resources | %d | 100%% |" % total)
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
        "| **fully green** (all stages ok) | %d | %.1f%% |" % (fully_green, pct)
    )
    out.append("")

    # ----- per-family table ----- #
    by_family = OrderedDict()
    for res in all_types:
        fam = family_of(res, families)
        by_family.setdefault(fam, []).append(res)

    out.append("## By service family")
    out.append("")

    def cell(rec, stage):
        if not rec:
            return "-"
        return rec["stages"].get(stage, "skip")

    for fam in sorted(by_family):
        members = sorted(by_family[fam])
        green = sum(
            1
            for r in members
            if store.get(r)
            and all(store[r]["stages"].get(s) == OK for s in STAGES)
        )
        out.append("### %s (%d/%d fully green)" % (fam, green, len(members)))
        out.append("")
        out.append(
            "| resource | validate | plan | apply | replan | destroy | "
            "highest | note |"
        )
        out.append("|---|---|---|---|---|---|---|---|")
        for r in members:
            rec = store.get(r)
            hi = rec["highest_stage"] if rec else None
            short = r
            pfx = "samsungcloudplatformv2_"
            if short.startswith(pfx):
                short = short[len(pfx):]
            note = (rec["note"] if rec else "") or ""
            note = note.replace("\n", " ").replace("|", "\\|")
            if len(note) > 80:
                note = note[:79] + "…"
            out.append(
                "| `%s` | %s | %s | %s | %s | %s | %s | %s |"
                % (
                    short,
                    cell(rec, "validate"),
                    cell(rec, "plan"),
                    cell(rec, "apply"),
                    cell(rec, "replan"),
                    cell(rec, "destroy"),
                    hi or "-",
                    note,
                )
            )
        out.append("")

    return "\n".join(out) + "\n"


# --------------------------------------------------------------------------- #
# main
# --------------------------------------------------------------------------- #
def main(argv):
    families = load_families()

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

    md = build_markdown(store, families)
    with open(COV_MD, "w", encoding="utf-8") as fh:
        fh.write(md)

    # Brief stdout summary for CI logs.
    green = sum(
        1
        for r in store.values()
        if all(r["stages"].get(s) == OK for s in STAGES)
    )
    sys.stderr.write(
        "coverage: %d resources tracked, %d fully green; wrote %s + %s\n"
        % (len(store), green, COV_JSON, COV_MD)
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
