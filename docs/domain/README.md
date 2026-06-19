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
| Human-readable | [`scp-domain-knowledge.md`](scp-domain-knowledge.md) | people | the *explanation* + provenance (account, dependency graph, cleanup, DBaaS basics) |

### Per-family pages (extend the shared page above)
| Page | Covers |
|---|---|
| [`dns.md`](dns.md) | private_dns ↔ VPC binding, hosted zone & record schemas, the #79 disassociate-then-delete step |
| [`vpc-peering.md`](vpc-peering.md) | create/approval/rule bodies, same-account-no-approval rule, the #61 `approver_vpc_name` provider/API contradiction |
| [`transit-gateway-private-nat.md`](transit-gateway-private-nat.md) | TGW + firewall/connection/rule/uplink_rule + private_nat schemas, the ACTIVE-connection "Connectable" precondition, `created_at` server-set trap, TGW max=3 |
| [`dbaas-cachestore-searchengine-sqlserver.md`](dbaas-cachestore-searchengine-sqlserver.md) | cachestore/searchengine/sqlserver create schemas, live server_type/engine_version lookup, FAILED-state outcomes, eventstreams crack pattern |

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
