#!/usr/bin/env python3
"""Render coverage/coverage.json into a self-contained GitHub Pages dashboard
(docs/index.html). Covers ALL provider resources (from coverage/resource_families.json),
not just the ones exercised, so the page shows the full coverage picture.

Usage: python3 scripts/build_coverage_html.py
"""
import json
import os
import datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COV = os.path.join(ROOT, "coverage", "coverage.json")
FAM = os.path.join(ROOT, "coverage", "resource_families.json")
OUT_DIR = os.path.join(ROOT, "docs")
OUT = os.path.join(OUT_DIR, "index.html")

STAGE_ORDER = ["validate", "plan", "apply", "replan", "update", "import", "destroy"]
# cell color classes
CLS = {
    "ok": "ok", "fail": "fail", "skip": "skip", "blocked": "blocked",
    "unsupported": "unsup", "": "none", None: "none",
}


def load(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return default


def main():
    cov = load(COV, {})
    fams = load(FAM, {})  # resource_type -> family

    # Build family -> [resource_type,...] over ALL known resources.
    by_family = {}
    for rtype, fam in fams.items():
        by_family.setdefault(fam, []).append(rtype)
    # include any covered resource missing from the family map
    for rtype in cov:
        if rtype not in fams:
            by_family.setdefault("(unmapped)", []).append(rtype)

    total = len(set(list(fams.keys()) + list(cov.keys())))

    # which stages actually appear (so update/import only show if used)
    present_stages = set()
    for rec in cov.values():
        present_stages.update((rec.get("stages") or {}).keys())
    stages = [s for s in STAGE_ORDER if s in present_stages] or ["validate", "plan", "apply", "replan", "destroy"]

    def stage_ok(rec, s):
        return (rec.get("stages") or {}).get(s) == "ok"

    with_run = len(cov)
    reach = {s: sum(1 for r in cov.values() if stage_ok(r, s)) for s in ["validate", "plan", "apply", "replan", "destroy"]}
    green = sum(1 for r in cov.values() if all(stage_ok(r, s) for s in ["validate", "plan", "apply", "replan", "destroy"]))

    def pct(n):
        return f"{100.0*n/total:.1f}%" if total else "0%"

    gen = datetime.datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC")

    # ---- HTML ----
    rows = []
    for fam in sorted(by_family):
        res = sorted(set(by_family[fam]))
        fam_green = sum(1 for r in res if r in cov and all(stage_ok(cov[r], s) for s in ["validate","plan","apply","replan","destroy"]))
        rows.append(f'<tr class="fam"><td colspan="{2+len(stages)}">{fam} '
                    f'<span class="cnt">{fam_green} green / {sum(1 for r in res if r in cov)} run / {len(res)} total</span></td></tr>')
        for r in res:
            rec = cov.get(r)
            cells = []
            for s in stages:
                v = (rec.get("stages") or {}).get(s) if rec else None
                cls = CLS.get(v, "none")
                txt = v if v else "—"
                cells.append(f'<td class="cell {cls}" title="{s}: {txt}">{txt}</td>')
            short = r.replace("samsungcloudplatformv2_", "")
            if rec:
                note = (rec.get("note") or "").replace('"', "&quot;")[:300]
                run = rec.get("last_run_url") or ""
                seen = (rec.get("last_seen") or "")[:10]
                last = f'<a href="{run}" target="_blank">{seen}</a>' if run else seen
                name_html = f'<span title="{note}">{short}</span>' if note else short
            else:
                last = '<span class="muted">no run yet</span>'
                name_html = f'<span class="muted">{short}</span>'
            rows.append(f'<tr><td class="rname">{name_html}</td>' + "".join(cells) + f'<td class="last">{last}</td></tr>')

    head_cells = "".join(f"<th>{s}</th>" for s in stages)
    funnel = f"""
      <div class="cards">
        <div class="card"><div class="num">{total}</div><div class="lbl">provider resources</div></div>
        <div class="card"><div class="num">{with_run}</div><div class="lbl">have a matrix run<br><span class="muted">{pct(with_run)}</span></div></div>
        <div class="card"><div class="num">{reach['apply']}</div><div class="lbl">reach apply<br><span class="muted">{pct(reach['apply'])}</span></div></div>
        <div class="card green"><div class="num">{green}</div><div class="lbl">fully GREEN<br><span class="muted">{pct(green)}</span></div></div>
      </div>
      <div class="bar">
        <span>validate {reach['validate']}</span><span>plan {reach['plan']}</span>
        <span>apply {reach['apply']}</span><span>replan {reach['replan']}</span><span>destroy {reach['destroy']}</span>
      </div>"""

    html = f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>SCP Terraform provider — coverage dashboard</title>
<style>
 :root{{--ok:#1a7f37;--fail:#cf222e;--skip:#6e7781;--unsup:#9a6700;--blocked:#bc4c00;--none:#eaeef2}}
 body{{font:14px/1.45 -apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;margin:0;color:#1f2328;background:#f6f8fa}}
 header{{background:#0d1117;color:#fff;padding:18px 24px}}
 header h1{{margin:0;font-size:18px}} header .sub{{color:#9aa4b2;font-size:12px;margin-top:4px}}
 main{{max-width:1100px;margin:0 auto;padding:20px}}
 .cards{{display:flex;gap:12px;flex-wrap:wrap;margin:8px 0 4px}}
 .card{{flex:1;min-width:150px;background:#fff;border:1px solid #d0d7de;border-radius:10px;padding:14px 16px}}
 .card.green{{border-color:var(--ok);box-shadow:0 0 0 1px var(--ok) inset}}
 .card .num{{font-size:30px;font-weight:700}} .card .lbl{{color:#57606a;font-size:12px}}
 .muted{{color:#8c959f}}
 .bar{{display:flex;gap:8px;flex-wrap:wrap;margin:10px 0 18px;font-size:12px;color:#57606a}}
 .bar span{{background:#fff;border:1px solid #d0d7de;border-radius:20px;padding:3px 10px}}
 table{{width:100%;border-collapse:collapse;background:#fff;border:1px solid #d0d7de;border-radius:10px;overflow:hidden}}
 th,td{{padding:6px 8px;text-align:left;border-bottom:1px solid #eaeef2;font-size:12.5px}}
 th{{background:#f6f8fa;position:sticky;top:0}}
 tr.fam td{{background:#eef2f6;font-weight:700;text-transform:capitalize}}
 tr.fam .cnt{{font-weight:400;color:#57606a;font-size:11px;margin-left:8px}}
 .rname{{font-family:ui-monospace,SFMono-Regular,Menlo,monospace}}
 td.cell{{text-align:center;font-weight:600;color:#fff;border-radius:4px}}
 .cell.ok{{background:var(--ok)}} .cell.fail{{background:var(--fail)}} .cell.skip{{background:var(--skip)}}
 .cell.unsup{{background:var(--unsup)}} .cell.blocked{{background:var(--blocked)}}
 .cell.none{{background:var(--none);color:#8c959f}}
 .legend{{margin:14px 0;font-size:12px;color:#57606a;display:flex;gap:10px;flex-wrap:wrap}}
 .legend b{{display:inline-block;width:12px;height:12px;border-radius:3px;vertical-align:-2px;margin-right:4px}}
 a{{color:#0969da;text-decoration:none}} a:hover{{text-decoration:underline}}
 .last{{white-space:nowrap;font-size:11.5px}}
</style></head><body>
<header>
  <h1>SCP Terraform provider — capability coverage</h1>
  <div class="sub">Generated {gen} · source: capability matrix (issue #13) · stages: validate → plan → apply → replan → destroy (+ optional update/import)</div>
</header>
<main>
  {funnel}
  <div class="legend">
    <span><b style="background:var(--ok)"></b>ok</span>
    <span><b style="background:var(--fail)"></b>fail</span>
    <span><b style="background:var(--skip)"></b>skip</span>
    <span><b style="background:var(--unsup)"></b>unsupported (no import)</span>
    <span><b style="background:var(--blocked)"></b>blocked</span>
    <span><b style="background:var(--none)"></b>no run</span>
    <span class="muted">· hover a resource for the last error/note</span>
  </div>
  <table>
    <thead><tr><th>resource</th>{head_cells}<th>last run</th></tr></thead>
    <tbody>
      {''.join(rows)}
    </tbody>
  </table>
  <p class="muted" style="margin-top:16px">Coverage store: <code>coverage/coverage.json</code> · regenerate locally with
  <code>python3 scripts/build_coverage.py out/capability-matrix.json &amp;&amp; python3 scripts/build_coverage_html.py</code>.</p>
</main></body></html>"""

    os.makedirs(OUT_DIR, exist_ok=True)
    with open(OUT, "w") as f:
        f.write(html)
    print(f"wrote {OUT}: {total} resources, {with_run} with-run, {green} green")


if __name__ == "__main__":
    main()
