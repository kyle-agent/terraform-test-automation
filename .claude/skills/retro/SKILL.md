---
name: retro
description: Milestone retrospective that extracts ACTIONABLE lessons from completed work into tasks/lessons.md so a future session does not re-discover the same trap. Use after a meaningful milestone/feature/sweep batch (not after pure exploration or a trivial 1-file change). Keywords: retro, retrospective, post-mortem, what did we learn, extract lessons, 회고, 교훈 정리. Adapted (MIT) from AlexZio00/claude-code-skills.
---

# /retro — extract lessons into tasks/lessons.md

Core principle: **a retro that produces "be more careful" has FAILED.** A retro that
produces "when merging a capability-matrix, key by scenario not the matrix `resource`
field" succeeds. Every lesson needs a concrete **trigger** + **action**.

**Skip** when: the session just started, was pure exploration, touched only trivial
scope (1 file, <10 min), or a checkpoint just covered the same area.

## Procedure

1. **Scope.** Name the milestone, its timespan, and the files/areas it touched.
2. **What went wrong (≤5).** For each friction point, find the ROOT CAUSE, not the
   symptom (symptom: "the merge mis-keyed"; root: "the matrix `resource` field is the
   first-declared resource, a prereq for self-contained scenarios").
3. **What went right (≤3).** Patterns worth reinforcing (e.g. "re-merged old matrices
   via the artifact API — no account needed").
4. **Pattern extract.** Recurring themes across the friction points.
5. **Write lessons.** For each durable lesson, append to `tasks/lessons.md` in the
   file's format (`### title` / `- trigger:` / `- do:` / `- conf/seen/obs`). Before
   writing, `grep` the title/trigger in `tasks/lessons.md`: if it already exists,
   bump `obs` + `seen` and raise `conf` instead of duplicating. Create the file from
   its own header template if missing.
6. **Summary (optional).** For a 3+-batch milestone, output a short conversation-only
   recap (do NOT write a separate retro doc — `coverage/HANDOFF.md` + `docs/findings/`
   already hold narrative state).

## Invariants
- Every lesson has a specific trigger AND an alternative action. No vague guidance.
- Root causes over symptoms.
- Code fixes discovered during a retro become pending tasks (or HANDOFF "next" items),
  NOT inline edits made during the retro.
- Lessons live in `tasks/lessons.md` only. Domain findings still go to `docs/findings/`.
