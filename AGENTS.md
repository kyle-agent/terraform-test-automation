# AGENTS.md — how this project runs (read this first)

This repository is developed and operated by a **team of AI agents** (multi-agent),
with humans able to read and steer everything they produce. This file is the single
entry point: any new session (human or agent) should read this first, then follow the
links. It does **not** duplicate the execution docs — it explains the *mission*, the
*agents*, and the *shared state* that let any session continue exactly where the last
one left off.

> Sister repo: the provider under test is the fork
> [`kyle-agent/terraform-provider-samsungcloudplatformv2`](https://github.com/kyle-agent/terraform-provider-samsungcloudplatformv2).
> This repo (`kyle-agent/terraform-test-automation`) is the test/verification harness.

---

## 1. Mission — two axes

This project has **two parallel goals ("axes")**. Every piece of work belongs to one.

### Axis ① — Verify the Terraform provider
Judge the quality of the `samsungcloudplatformv2` Terraform provider as an
independent third party, and drive fixes.
- **Static analysis** of the provider Go source (schema modifiers, waiters, error
  handling, ImportState, panics) **plus real execution** (apply/replan/destroy) and
  analysis of the observed behaviour.
- **Benchmark / reference** against how mature providers (AWS, etc.) behave, and
  against the SCP Open API ground truth.
- **Register findings as issues on the fork** repo, one defect at a time, with
  concrete reproduction + diff evidence.
- **Continuously re-sync the latest provider release** and re-verify (catch
  regressions / confirm fixes).
- Method detail: [`docs/PROVIDER_VERIFICATION.md`](docs/PROVIDER_VERIFICATION.md).
  Confirmed defects: [`docs/PROVIDER_ISSUES.md`](docs/PROVIDER_ISSUES.md).

### Axis ② — Maximize test coverage & regression-test
Exercise as many provider resources as possible through the full lifecycle and keep
them green over time.
- Per-resource **capability matrix** (validate → plan → apply → replan → update →
  import → destroy → destroy_verify).
- Single source of truth: [`coverage/registry.yaml`](coverage/registry.yaml)
  (one entry per scenario). Dashboards in [`COVERAGE.md`](COVERAGE.md).
- Strategy & parallel architecture: [`docs/TEST_STRATEGY.md`](docs/TEST_STRATEGY.md).
  Execution: [`docs/dynamic-workflow.md`](docs/dynamic-workflow.md).
  Live worklist: [`docs/roadmap.md`](docs/roadmap.md) +
  [`coverage/HANDOFF.md`](coverage/HANDOFF.md).

---

## 2. The agents

One **orchestrator** coordinates; each **role agent** owns a slice of the work and a
set of shared-state files. Agents communicate **only through git-tracked files** (and
GitHub issues / Actions) so that any session can be reconstructed from the repo alone.

| Agent | Axis | Owns / produces | Spec |
|---|---|---|---|
| **Orchestrator** | both | picks the next unit of work, sequences agents, enforces guardrails | [`docs/agents/orchestrator.md`](docs/agents/orchestrator.md) |
| **Provider-Verification** | ① | static+dynamic analysis, defect write-ups | [`docs/agents/provider-verification-agent.md`](docs/agents/provider-verification-agent.md) |
| **Coverage-Regression** | ② | `registry.yaml`, scenarios, capability-matrix runs | [`docs/agents/coverage-regression-agent.md`](docs/agents/coverage-regression-agent.md) |
| **API-Info-Collector** | both | latest API/service facts → domain knowledge inputs | [`docs/agents/api-info-collector-agent.md`](docs/agents/api-info-collector-agent.md) |
| **API-Evaluator** (3rd-party) | ① | independent UX/quality assessment of the provider's API | [`docs/agents/api-evaluator-agent.md`](docs/agents/api-evaluator-agent.md) |
| **Issue-Registrar** | ① | opens/updates/reopens issues on the fork | [`docs/agents/issue-registrar-agent.md`](docs/agents/issue-registrar-agent.md) |
| **Dashboard** | ② | builds `COVERAGE.md` / coverage JSON / Pages | [`docs/agents/dashboard-agent.md`](docs/agents/dashboard-agent.md) |
| **Domain-Knowledge-Curator** | both | maintains `docs/domain/` + `coverage/domain.yaml` | [`docs/agents/domain-knowledge-curator-agent.md`](docs/agents/domain-knowledge-curator-agent.md) |

```
                         ┌──────────────────┐
            ┌───────────►│   Orchestrator   │◄───────────┐
            │            └───┬───────┬───────┘            │
            │  reads domain  │       │  picks work        │ status
            │  knowledge     ▼       ▼                    │
   ┌────────┴────────┐  ┌─────────┐  ┌─────────────┐  ┌───┴────────┐
   │ Domain-Knowledge│  │Provider-│  │  Coverage-  │  │ Dashboard  │
   │     Curator     │  │  Verify │  │ Regression  │  │            │
   └────┬───────▲────┘  └────┬────┘  └──────┬──────┘  └────────────┘
        │       │            │              │
  writes│       │ feeds      ▼              ▼
docs/domain/ ┌──┴──────────────┐     ┌──────────────┐
coverage/    │ API-Info-Collect│     │Issue-Registrar│──► fork issues
domain.yaml  │ + API-Evaluator │     └──────────────┘
             └─────────────────┘
```

### Runnable agent definitions
Each agent is installed as a **Claude Code subagent** under
[`.claude/agents/`](.claude/agents/) (git-tracked, so available in every session). Any
session can invoke one by name (e.g. `scp-orchestrator`, `coverage-regression`,
`provider-verification`, `api-info-collector`, `api-evaluator`, `issue-registrar`,
`coverage-dashboard`, `domain-knowledge-curator`). Each definition is a thin launcher
that points at this file + the full spec in `docs/agents/`.

### Practical mapping (today)
The agents are **roles**, not always separate processes. They run as Claude Code
subagents (`.claude/agents/`) plus GitHub Actions workflows; the role boundaries below
define *who is responsible for what* and *which files are the contract*, so the system
behaves identically no matter how many sessions/processes are live.
- Verification/coverage execution → GitHub Actions: `coverage-sweep-pool.yml`,
  `dbaas-probe.yml`, `api-reaper.yml`, `inventory.yml` (+ `regression.yml`,
  `nightly.yml`, `dynamic-regression.yml`).
- Cleanup/leak handling → API reaper (`cmd/api_reaper/`) + `scp-api` skill.

---

## 3. Shared state (the contract between agents & sessions)

Everything an agent needs to resume is in git. Read these, in order:

| File | What it holds | Who writes |
|---|---|---|
| `AGENTS.md` (this) | mission, agents, bootstrap | humans + curator |
| `docs/roadmap.md` | end goal + live work breakdown | orchestrator |
| `coverage/HANDOFF.md` | rolling session handoff (latest findings, account state) | every agent |
| `tasks/lessons.md` | correction rules / recurring traps (so a session doesn't re-discover a bug) | `/retro`, `/session-checkpoint` |
| `coverage/registry.yaml` | per-scenario status (axis ②) | coverage-regression |
| `docs/PROVIDER_ISSUES.md` | confirmed provider defects (axis ①) | provider-verification + issue-registrar |
| `coverage/domain.yaml` | machine-readable SCP domain knowledge | domain-knowledge-curator |
| `docs/domain/` | human-readable SCP domain knowledge | domain-knowledge-curator (humans edit) |

**Rule:** agents must keep these files truthful and current. A finding that is not
written to one of these files does not exist for the next session.

---

## 4. Session bootstrap (how to continue identically)

A fresh session (any agent) does — or just runs **`/session-start`**, which automates
steps 1–4 below (read-only) and names Priority 1; checkpoint state at the end with
**`/session-checkpoint`**, and capture durable traps with **`/retro`** (skills live in
[`.claude/skills/`](.claude/skills/)):
1. Read `AGENTS.md` (this) → know the mission + which agent you are.
2. Read `docs/roadmap.md` + `coverage/HANDOFF.md` + `tasks/lessons.md` → current state,
   next work, and correction rules to avoid re-tripping.
3. Load domain knowledge: `coverage/domain.yaml` (machine) and the relevant
   `docs/domain/*` page (human) for the service you're touching.
4. For axis ②: read `coverage/registry.yaml` for scenario status.
   For axis ①: read `docs/PROVIDER_ISSUES.md` for open/confirmed defects.
5. Do the work for your role (see your spec in `docs/agents/`).
6. **Write back**: update the shared-state file(s) you own + append to
   `coverage/HANDOFF.md`. Commit & push to the working branch.

---

## 5. Guardrails (apply to every agent)
- **Never weaken a test/assertion to make it pass.** A real provider bug stays
  failing and becomes an issue on the fork.
- **Leak-0**: every integration run cleans up; the reaper is the safety net. The SCP
  account VPC quota is **5** — a leaked VPC blocks everyone.
- **Dedicated test account only** for destructive actions (guarded by
  `EXPECTED_ACCOUNT_ID`).
- **Domain knowledge is AI-generated but human-owned**: keep `docs/domain/` readable
  and let humans override; `coverage/domain.yaml` must stay in sync with it.
- Confirm before outward-facing/irreversible actions (opening issues, mass deletes).
