---
name: session-checkpoint
description: Preserve in-progress state before context compression, task switching, or ending a session — update coverage/HANDOFF.md §0 with the next actions/decisions/in-flight runs and append any durable lessons to tasks/lessons.md. Use on checkpoint / save progress / end session / handoff / compact / 체크포인트 / 핸드오프 저장. Adapted (MIT) from AlexZio00/claude-code-skills, wired to this repo's existing coverage/HANDOFF.md.
---

# /session-checkpoint — preserve state into HANDOFF.md

Capture what context compression would destroy, into the repo's existing handoff —
do NOT invent a new memory/ store.

## Procedure

1. **Extract what compression would lose.** Open decisions, in-progress work, the
   user's stated priorities, in-flight CI runs (run ids to harvest), known leaks /
   VPC-quota state, error→resolution pairs, and the immediate next step. Plus dead ends
   (what was tried and ruled out) so they aren't re-attempted.
2. **Write the handoff.** Prepend a new dated block to the top of `coverage/HANDOFF.md`
   §0 (LATEST), matching the existing section style. Forward-looking only: next actions,
   current state, open decisions, in-flight runs, blockers. Remove items that are now
   done. Keep §0 tight (a few screens) — older sessions stay as lower §s.
   - Update the `**Branch:**` / `**Last updated:**` header lines.
3. **Promote durable lessons.** Any correction rule worth keeping across sessions →
   append to `tasks/lessons.md` (grep first; bump `obs`/`seen` if it exists). One-off
   domain facts go to `docs/findings/`, not the handoff.
4. **Repeated-workflow note (proposal only).** If the same multi-step workflow ran ≥3×
   this session, note it as a candidate `.claude/skills/<name>` — propose, do NOT
   auto-create.
5. **Preservation check.** Before declaring done, confirm the handoff names: every open
   decision, every in-flight run id, the next action, and any uncommitted/unpushed work.
6. **Compact guidance.** Tell the user it's safe to `/compact` (a CLI built-in this
   skill cannot call).

## Invariants
- One handoff file (`coverage/HANDOFF.md`); no `*-v2.md` copies.
- §0 LATEST is forward-looking; narrative of "what was done" belongs in the commit log
  and lower §s, not the next-action block.
- Never claim a checkpoint is complete while an in-flight run id or unpushed commit is
  unrecorded.
- Skill proposals require user approval before creation.
