---
name: knowledge-ops
description: Where a piece of knowledge belongs in this workspace, and how to keep the cross-service memory graph (the memory MCP server, knowledge/memory.jsonl) - entities, relations and dated observations about services, tables, endpoints, events and providers. Use when the user says "remember that", "save this", "what do we know about X", or "which services touch Y"; when /task finish turns up a fact that outlives the task; or when deciding between the memory graph, auto-memory, a learned file, and a task's docs.
metadata:
  origin: ECC
---

# Knowledge Operations

Every fact in this workspace has one home. Most already have an obvious one; this
skill is for the ones that do not, and for keeping the one store nothing else
covers — the cross-service memory graph.

## Where a fact belongs

| The fact is about | Home | Written by |
|---|---|---|
| One task — what was tried, decided, built | `docs/<date>_<task>/` — `prd.md`, `plan.md`, `log.md` | `/plan-prd`, `/plan`, `/save-session`, `/task finish` |
| How Claude should work for this user — preferences, corrections | auto-memory (`MEMORY.md` and its files) | the session, when told |
| How one repo writes code — its logger, its test layout | `.claude/learned/<repo>/<skill>.md` | `/learn` |
| What a repo's team requires | that repo's `AGENTS.md` | the team — never this workspace |
| Code structure — who calls what | the `graph-<repo>` MCP servers | `/graph` |
| **How the services relate, and what holds across tasks** | **the memory graph** | **this skill** |

The memory graph is for the last row only. Questions it answers that nothing else
does: *which services read this column?*, *what do we know about this provider's
API?*, *who publishes this event, and who consumes it?*

Never copy a fact into a second home. If it is in a learned file or a task's log, the
memory graph may point at it — never restate it.

## The memory graph

The `memory` MCP server (`@modelcontextprotocol/server-memory`), storing
`knowledge/memory.jsonl` — gitignored, per machine, written into `.mcp.json` by
`graph.sh`. Three kinds of record:

- **Entity** — a named thing, with a type
- **Relation** — a directed, active-voice link between two entities
- **Observation** — one fact attached to an entity

### Naming

| Entity type | Name | Example |
|---|---|---|
| `service` | the repo alias | `orders` |
| `table` | `<service>.<table>` | `orders.order_items` |
| `endpoint` | `<service> <METHOD> <path>` | `orders POST /v2/orders/hold` |
| `event` | `<event name>` | `order_held` |
| `provider` | the company | `acme-pay` |
| `decision` | short kebab slug | `shared-card-id` |

Relations, always active voice: `owns`, `reads`, `writes`, `calls`, `publishes`,
`consumes`, `depends_on`, `supersedes`.

### Every observation is dated and sourced

End each observation with its source: `(task <task>, YYYY-MM-DD)` or
`(code <repo>:path, YYYY-MM-DD)`. An observation with no source
cannot be checked, and one with no date cannot be known to be stale — and the graph
has no other way to tell.

## Reading

Search before answering any "what do we know about…" question, and before writing:

- `search_nodes` with the key term — it matches names, types and observation text as
  substrings, not meaning, so try the table name, the service, and the provider
- `open_nodes` on what it finds, to see the relations

Treat what comes back as a lead, not as truth: check a claim against the code or the
task's docs before acting on it, and say how old it is.

## Writing

1. **Search first.** If the entity exists, `add_observations`; never create a second
   entity for the same thing under a different name.
2. **Ask before writing.** Show the entities, relations and observations you intend to
   add, and write only after the user agrees. The write tools prompt for that reason.
3. **Correct, do not pile up.** When a fact changes, `delete_observations` the old one
   and add the new one with its date — a graph with both is wrong half the time.
4. **No secrets.** No keys, tokens, credentials or customer data, ever — the file is
   plain text on disk.

### When to offer a write

- **At `/task finish`**, when the wrap-up's *Worth remembering* holds something about
  how services relate that the next task will need — not a description of the task.
- **When the user says** "remember that…" about a service, a table, a provider.
- **When a session learns a cross-service fact the hard way** — a field another
  service depends on, a provider behaving unlike its docs.

Do not mirror a task log, a plan, or code structure into it. If the next session could
find it with `grep docs/` or a `graph-<repo>` query, it does not belong here.

## Quality gate

Before finishing any write:

- searched first; no duplicate entity
- every observation dated and sourced
- nothing secret
- the fact is cross-service or cross-task — not one task's story, not one repo's
  convention
