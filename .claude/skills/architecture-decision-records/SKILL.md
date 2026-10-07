---
name: architecture-decision-records
description: Capture architectural decisions as short ADRs with context, alternatives considered, and consequences. Use when the user says 'record this decision' or 'ADR this', when a PRD or plan chooses between frameworks, databases, or patterns, when a trade-off is settled during a task, or when someone asks why the code is shaped the way it is.
metadata:
  origin: ECC
---

# Architecture Decision Records

Capture architectural decisions as they happen. Instead of living only in chat threads,
PR comments, or someone's memory, the reasoning is written down where the next person
will look for it.

## Where an ADR goes

Look for an existing home first, in the working directory of the repo the decision is
about (`task.sh where <task> <repo>`):

1. **The repo already keeps ADRs** — its `AGENTS.md` names a location, or a directory such
   as `docs/adr/` or `docs/decisions/` exists. Follow its numbering, format, and index. The
   ADR is then a change to that repo: it is written during the task and ships in the
   task's pull request like any other file.
2. **It does not** — record the ADR as a supporting file of the task:
   `docs/<YYYY-MM-DD>_<task>/adr-<NNNN>-<slug>.md`, found with `ls -d docs/*_<task>/`.
   Number it by globbing `docs/*/adr-*.md` across all tasks and taking the next number,
   so the workspace's decisions read as one sequence.

Never create a new ADR directory inside a service repo on your own: whether a repo keeps
ADRs is its team's call. If one clearly should, say so and let the user decide.

Always present the draft and get the user's approval before writing it. A declined draft
is discarded.

## When to Activate

- User explicitly says "let's record this decision" or "ADR this"
- A PRD, plan, or `product-capability` handoff chooses between significant alternatives (framework, library, pattern, database, API style)
- User says "we decided to..." or "the reason we're doing X instead of Y is..."
- User asks "why did we choose X?" — read the existing ADRs first

## ADR Format

The lightweight format proposed by Michael Nygard:

```markdown
# ADR-NNNN: [Decision Title]

**Date**: YYYY-MM-DD
**Status**: proposed | accepted | deprecated | superseded by ADR-NNNN
**Deciders**: [who was involved]
**Task**: `<task>` (when recorded during one)

## Context

[2-5 sentences: the situation, constraints, and forces at play]

## Decision

[1-3 sentences stating the decision clearly]

## Alternatives Considered

### Alternative 1: [Name]
- **Pros**: [benefits]
- **Cons**: [drawbacks]
- **Why not**: [specific reason this was rejected]

## Consequences

### Positive
- [benefit]

### Negative
- [trade-off]

### Risks
- [risk and mitigation]
```

## Recording one

1. **Identify the decision** — the core architectural choice being made
2. **Gather context** — what problem prompted it, and which constraints apply
3. **Document alternatives** — what else was considered, and why each lost
4. **State consequences** — what becomes easier and what becomes harder
5. **Number it** — per *Where an ADR goes*
6. **Confirm and write** — present the draft; write only after approval
7. **Link it** — mention the ADR in the task's `plan.md` or `prd.md` where the decision
   shows up, so the reasoning is reachable from the work it shaped

## Reading existing ADRs

When someone asks "why did we choose X?", check the repo's own ADR location, then
`docs/*/adr-*.md`. Present the Context and Decision of any match. If there is none, say so
and offer to record one now — a backfilled ADR notes the original date of the decision.

## Decision Detection Signals

**Explicit** — "Let's go with X", "We should use X instead of Y", "The trade-off is worth
it because…", "Record this as an ADR".

**Implicit** (suggest an ADR — never auto-create one):
- Comparing two frameworks or libraries and reaching a conclusion
- Making a schema design choice with stated rationale
- Choosing between architectural patterns (monolith vs services, REST vs GraphQL, sync vs events)
- Deciding an authentication or authorization strategy
- Selecting deployment infrastructure after weighing alternatives

## What Makes a Good ADR

### Do
- **Be specific** — "Use Prisma ORM", not "use an ORM"
- **Record the why** — the rationale matters more than the what
- **Include rejected alternatives** — the next person needs to know what was considered
- **State consequences honestly** — every decision has trade-offs
- **Keep it short** — readable in two minutes
- **Use present tense** — "We use X", not "We will use X"

### Don't
- Record trivial decisions — naming and formatting do not need ADRs
- Write essays — a Context section over ten lines is too long
- Omit alternatives — "we just picked it" is not a rationale
- Let ADRs go stale — a superseded ADR links its replacement

## ADR Lifecycle

```
proposed → accepted → [deprecated | superseded by ADR-NNNN]
```

A superseded ADR is not deleted or rewritten; its status changes and it links forward.
Like a closed task's log, it is a record of what was true when it was written.
