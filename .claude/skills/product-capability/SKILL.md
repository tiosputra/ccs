---
name: product-capability
description: Translate a PRD into an implementation-ready capability plan that exposes constraints, invariants, states, data ownership, and unresolved decisions before multi-repo work starts. Use after a task's PRD is approved and before or while planning it, when the change crosses several repos or services and the constraints that must hold are still implicit.
metadata:
  origin: ECC
---

# Product Capability

This skill turns product intent into explicit engineering constraints.

Use it when the gap is not "what should we build?" — the PRD answered that — but "what
exactly must be true before implementation starts?"

## Where it sits in the flow

After Gate 1, before or during `/plan`. The PRD says what and why; the plan says which
files change. Between them, a change that crosses repos often carries rules that live only
in someone's head — who owns a record, which state transitions are legal, what must happen
when a downstream call fails. This skill writes those down once.

Its output is the supporting file `capability.md` in the task's directory
(`ls -d docs/*_<task>/`). Two things it does **not** hold, because they already have homes:

- **Requirements and acceptance criteria** — those are the PRD's. A gap found here goes
  back into `prd.md` as a decision or an Open Question.
- **What consumers see change at a boundary** — endpoints, fields, events, error shapes.
  That is `api-contract.md`, written with `contract-first`. Reference its entries by
  number rather than restating them.

A single-repo change with obvious constraints does not need this. Skip it rather than
produce ceremony.

## When to Use

- The approved PRD crosses several repos, services, or teams
- Product intent is clear, but lifecycle, data ownership, or policy implications are still fuzzy
- Reviewers keep restating the same hidden assumptions
- A later milestone will need the same constraints and should not rediscover them

## Non-Negotiable Rules

- Do not invent product truth. Mark unresolved questions explicitly.
- Separate user-visible promises from implementation details.
- Call out what is fixed policy, what is architecture preference, and what is still open.
- If the request conflicts with existing repo constraints — including a repo's `AGENTS.md` —
  say so clearly instead of smoothing it over.

## Inputs

Read only what is needed:

1. The task's `prd.md` — the intent, scope, and acceptance criteria
2. Current architecture — the relevant code, schemas, routes, and existing contracts in each
   repo's working directory (`task.sh where <task> <repo>`)
3. Any `api-contract.md` already written for the task
4. Delivery constraints — auth, compliance, rollout, backwards compatibility, performance

## Core Workflow

### 1. Restate the capability

Compress the ask into one precise statement: who the user or operator is, what new
capability exists after this ships, and what outcome changes because of it. If this
statement is weak, the implementation will drift.

### 2. Resolve capability constraints

Extract the constraints that must hold before implementation:

- business rules
- invariants
- trust boundaries
- data ownership — which repo is the source of truth for each record
- lifecycle states and legal transitions
- rollout / migration requirements
- failure and recovery expectations

### 3. Define the implementation-facing contract

- actors and surfaces
- required states and transitions
- inputs and outputs between the repos (pointing at `api-contract.md` entries)
- data model implications
- security / policy constraints
- observability and operator requirements

### 4. Hand off

End with exactly one of:

- **ready for `/plan`** — the constraints are settled
- **needs architecture review first** — a choice here deserves an ADR (`architecture-decision-records`)
- **needs product clarification first** — the open question goes back to the PRD and the user

## Output Format

```markdown
# Capability: {Task Name}

*Created {YYYY-MM-DD} · Last updated {YYYY-MM-DD}*

## Capability
{one paragraph}

## Constraints
- {fixed rule, invariant, or boundary} — {fixed policy | architecture preference}

## Data ownership
| Record | Source of truth | Readers |
|---|---|---|

## States and transitions
{state list, and which transitions are legal — a table or a small diagram}

## Between repos
- {repo} -> {repo}: {what flows} — see `api-contract.md` #{n}

## Failure and recovery
- {what fails} -> {what must be true afterwards}

## Non-goals
- {what this capability explicitly does not own}

## Open questions
- [ ] {blocker} — settled by {who or what}

## Handoff
{ready for /plan | needs architecture review | needs product clarification}
```

## Good Outcomes

- Product intent is concrete enough to implement without rediscovering hidden constraints mid-PR.
- Reviewers have a durable artifact instead of relying on memory.
- A later milestone's plan reads `capability.md` instead of re-deriving it.
