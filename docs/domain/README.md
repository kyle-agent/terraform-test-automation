# SCP domain knowledge

This folder is the **human-readable** SCP domain knowledge that the agents rely on to
act correctly (e.g. *"to create a virtual server you must first create a VPC and a
subnet"*). It is generated and maintained by the
[Domain-Knowledge-Curator agent](../agents/domain-knowledge-curator-agent.md), but it
is **human-owned**: anyone may read, correct, or override it.

## Two synchronized forms
| Form | File | Audience | Role |
|---|---|---|---|
| Machine-readable | [`../../coverage/domain.yaml`](../../coverage/domain.yaml) | agents | the *contract* agents execute against (prereqs, ordering, constraints) |
| Human-readable | [`scp-domain-knowledge.md`](scp-domain-knowledge.md) | people | the *explanation* + provenance |

**Invariant:** the two must stay in sync. The YAML is the executable truth; the prose
explains *why* and records where each fact came from. When you change one, change the
other.

## How facts get here
1. **API-Info-Collector** gathers live API/service facts.
2. **Provider-Verification** / **Coverage-Regression** contribute behaviours observed
   in real runs (root causes, what a bootstrap actually needed).
3. **Domain-Knowledge-Curator** distills them into `domain.yaml` + this prose, tagging
   **source** and **confidence**.
4. Humans review and may override anything.

## Conventions
- Every non-obvious fact cites a **source** (run id, probe, doc, or provider source
  line) and a **confidence** (confirmed / inferred).
- Keep it organized by **service family**. Prefer dependency facts that an agent can
  act on ("X requires Y first") over prose.
