---
name: session-start
description: Reopen this project in a fresh session — load the handoff + lessons, name the single next action, and flag relevant correction rules before doing any work. Use at the start of a session or when the user says resume / pick up / continue / 세션 시작 / 이어서. Read-only. Adapted (MIT) from AlexZio00/claude-code-skills, wired to this repo's existing coverage/HANDOFF.md (no separate memory/ store).
---

# /session-start — resume the coverage work

Read-only bootstrap. Produces a briefing that names **Priority 1** (a concrete next
action) — a "ready" signal without a named next action has failed.

## Procedure

1. **Mission (always).** Read `AGENTS.md` (2-axis mission + multi-agent architecture +
   bootstrap). This is the repo's canonical entrypoint.
2. **Handoff.** Read `coverage/HANDOFF.md` — the §0 latest-session block has the next
   actions, open decisions, in-flight runs, and known leaks/blockers. Extract: the most
   urgent next action, open decisions, and any pending sweep/leak to confirm.
3. **Lessons.** Read `tasks/lessons.md`. Flag the correction rules relevant to what §0
   says you're about to touch (e.g. coverage-merge → the scenario-keying lesson;
   provider sweep → the build-ref lesson). Prefer high-`conf`, recently-`seen` ones.
4. **Ground truth.** Skim `COVERAGE.md` funnel + `coverage/registry.yaml` status counts
   (`green`/`broken`/`untested`/`excluded`) so the briefing reflects reality, not just
   the handoff's prose. `untested` count > 0 means a sweep is mid-flight or pending.
5. **Ready signal.** Output a short briefing:
   - **Priority 1:** <the single next concrete action>
   - **Open decisions:** <from HANDOFF §0, if any>
   - **Flagged lessons:** <the trigger lines that apply today>
   - **Alerts:** <in-flight runs to harvest, leaks to reap, VPC-quota state>

## Invariants
- Read-only. The only allowed write is promoting an overdue HANDOFF item — otherwise
  no edits.
- Missing files skip silently (a fresh clone may lack `tasks/lessons.md`).
- MUST name a concrete Priority 1. "Everything looks fine" is not a ready signal.
- Do not start executing until the briefing is shown and (if there are open decisions)
  the user has steered.
