---
description: Restate requirements, assess risks, and create step-by-step implementation plan for a task's space. WAIT for user CONFIRM before touching any code.
argument-hint: "[task description | docs/<YYYY-MM-DD>_<task>/prd.md]"
allowed-tools: Bash(.claude/scripts/space.sh:*), Read, Write, Edit, Glob, Grep
---

# Plan Command

This command creates a comprehensive implementation plan before writing any code. It accepts either free-form requirements or a PRD markdown file.

Run inline by default. Do not call the Task tool or any subagent by default. This keeps `/plan` usable from plugin installs that ship commands without agent files.

## What This Command Does

0. **Bind the task** - resolve which space this plan is for, and confirm it exists
1. **Restate Requirements** - Clarify what needs to be built
2. **Identify Risks** - Surface potential issues and blockers
3. **Create Step Plan** - Break down implementation into phases
4. **Write the API Contract** - if the work changes anything a consumer can observe
5. **Wait for Confirmation** - MUST receive user approval before proceeding

## When to Use

Use `/plan` when:
- Starting a new task
- Making significant architectural changes
- Working on complex refactoring
- Multiple files/components will be affected
- Requirements are unclear or ambiguous

## Step 0: Bind the Task

A plan is only valid for one task's space. Resolve the binding before anything else.

**From a PRD** (`docs/<YYYY-MM-DD>_<task>/prd.md`): read its `## Task` table. That gives
the task name, repos, branch, and source branch. Confirm the space is really there:

```bash
.claude/scripts/space.sh list <task>
```

**Without a PRD** (free-form text): derive a kebab-case `<task>` name from the request,
run `.claude/scripts/space.sh list` to see whether that space already exists, and:

- If it exists, use it, and read `spaces/<task>/.space` for the recorded branch and base.
- If it does not, ask the user for the **repos** and the **source branch**, then open it:

  ```bash
  .claude/scripts/space.sh add <task> <repos> --from <source-branch>
  ```

  The source branch is required. Never default it to `origin/main` on the user's behalf.

Once bound, the session works only in that space. Every path in the plan starts with
`spaces/<task>/<repo>/`. A plan that names a path under `repos/` is wrong — `repos/` is
read-only (see `CLAUDE.md`); rewrite it before presenting the plan.

If the work turns out to need a service that is not in the space, stop and say so.
Adding it is `/space add <task> <repo>` — the user's call, not an assumption.

### This command is where space knowledge stops

Spaces are decided here and in `/plan-prd`. Everything downstream — the `tdd-workflow`
skill, the reviewer agents, the pattern skills — is deliberately space-blind: they know
only a **working directory** and, where it matters, a **base ref**. So the plan must spell
both out. Hand down a path, never a task name, and never make a skill go looking for a
space of its own.

## How It Works

The assistant will:

1. **Bind the task** and confirm the space exists (Step 0)
2. **Analyze the request** and restate requirements in clear terms
3. **Ground the plan** in codebase patterns read from the space's worktrees
4. **Break down into phases** with specific, actionable steps
5. **Identify dependencies** between components
6. **Assess risks** and potential blockers
7. **Estimate complexity** (High/Medium/Low)
8. **Present the plan** and WAIT for your explicit confirmation

## Input Modes

| Input | Mode | Behavior |
|---|---|---|
| `docs/<YYYY-MM-DD>_<task>/prd.md` | PRD artifact mode | Read the PRD's Task block and milestones, pick the next pending milestone, and write the plan beside it in the same directory |
| Any other markdown path | Reference mode | Read the file as context, bind the task per Step 0, produce an inline plan |
| Free-form text | Conversational mode | Bind the task per Step 0, produce an inline plan |
| Empty input | Clarification mode | Ask what should be planned |

**The plan lives in the task's own directory**, next to the PRD it came from —
`docs/<YYYY-MM-DD>_<task>/`. That directory already exists in PRD artifact mode: it is the
one holding the PRD you were handed. Never create a second directory for the same task,
and never guess its date — the PRD's path is the directory.

**Naming — one plan per milestone.** A PRD's `Delivery Milestones` table is planned one row
at a time, so each milestone gets its own file in that directory:

| Situation | Plan file |
|---|---|
| Milestone 1, or a PRD with no milestones table | `plan.md` |
| Milestone `<N>`, `<N>` > 1 | `plan-m<N>.md` |
| Free-form or reference mode | inline, or `docs/<date>_<task>/plan.md` if the user wants a file |

Milestone 1 is plain `plan.md` because most tasks only ever have one. The moment a second
milestone is planned it becomes `plan-m2.md`; `plan.md` is never renamed.

Never write two milestones to the same file — milestone 2 must not overwrite the plan that
produced milestone 1, because that plan is the record its TDD evidence points back to.
Before writing, `ls docs/*_<task>/` and see which plans are already there.

In free-form mode there may be no task directory yet. Create `docs/<today>_<task>/` with
today's `date +%F` only if the user wants the plan written to a file.

If a plan for **this same milestone** already exists, read it and revise it in place. A
different milestone always means a new file.

Update only the selected row of the milestones table from `pending` to `in-progress`, and
set that row's `Plan` cell to the filename you just wrote (`plan.md`, `plan-m2.md`) — each
row ends up pointing at its own plan, and a bare filename is enough because it sits in the
same directory. If the PRD uses an older layout — `.claude/PRPs/prds/` with `Implementation
Phases`, or a top-level `prds/` and `plans/` pair — read it as it is; do not migrate a
closed task's paths to satisfy the current convention.

## Pattern Grounding

Before writing the plan, search the task's worktrees — `spaces/<task>/<repo>/`, never
`repos/` — for conventions the implementation should mirror. Capture the top example for
each relevant category with file references:

| Category | What to capture |
|---|---|
| Naming | File, function, type, command, or script naming in the affected area |
| Error handling | How failures are raised, returned, logged, or handled gracefully |
| Logging | Levels, format, and what gets logged - check it against the `logging` skill and the repo's `.claude/learned/<repo>/logging.md` |
| Data access | Repository, service, query, or filesystem patterns |
| Tests | Test file location, framework, fixtures, and assertion style |

If no similar code exists, state that explicitly. Do not invent a pattern.

## API Contract

Anything a consumer can observe changing at a boundary is written down separately, in
`docs/<YYYY-MM-DD>_<task>/api-contract.md`. Frontend and mobile read that file - often
through an LLM of their own - and build against it while the provider is still being
written. It is the one task artifact with a reader outside this workspace, so it must
stand on its own: assume no plan, no PRD, and no knowledge of spaces.

**Write one when the milestone changes any of these:**

| Change | Example |
|---|---|
| A new endpoint | `POST /v4/booking/hold` |
| A new field on an existing response | `cancellationReason` appears on a booking |
| A changed field | its type, nullability, enum values, or meaning |
| A new socket event, or a new payload on an existing one | `booking` on the player namespace |
| An error a consumer must handle differently | `409 SLOT_TAKEN` |

**Skip it** when the milestone is invisible from outside the service - an internal
refactor, a query rewrite, a migration with no response change. Say so in one line in the
plan's Summary rather than writing an empty file; a contract nobody needed is noise the
next reader has to rule out.

Read the `contract-first` skill before writing it. The rules that bite most often here:
design from what the consumer must render rather than from a database row, state
nullability and enum values explicitly, and change the contract before the implementation
rather than recording it afterwards.

**One file per task, appended per milestone**, the same way `testing.md` is one file with a
section per repo. Read it before writing, add or revise only your milestone's entries,
never start a second file.

### Where the truth lives after merge

This file is authoritative for the boundary *during* the task, when the provider does not
exist yet to be inspected. Each repo already generates a spec that takes over once the code
lands, and every entry names the one it will end up in:

| Repo | Generated spec | Note |
|---|---|---|
| `backend` | `src/openapi/spec/` - split JSON under `paths/` and `components/schemas/`, served at `/docs` | HTTP only |
| `sport`, `player` | `docs/swagger.yaml` - generated from handler annotations | HTTP only |
| any socket.io event | none | `src/services/io/<domain>/` generates nothing, so this file stays the only written contract |

Socket events are the case that most needs writing down, precisely because nothing
generates them.

### Template

Use only the entry kinds the milestone actually contains. Dates come from `date +%F`.

````markdown
# API Contract: {Task Name}

*Task `<task>` · created {YYYY-MM-DD} · last updated {YYYY-MM-DD}*
**Provider**: {repo} · **Consumers**: {web, mobile, admin} · **Plan**: `plan.md`

> The agreed shape of every boundary this task changes, written before the provider
> exists so consumers can build against it. If the implementation needs a different
> shape, this file changes first and the change is reviewed - not the other way round.

## Changes

| # | Kind | Boundary | Change | Breaking |
|---|---|---|---|---|
| 1 | endpoint | `POST /v4/booking/hold` | new | no |
| 2 | field | `GET /v4/booking/{id}` -> `data.cancellationReason` | added | no |
| 3 | socket | player ns, event `booking_held` | new | no |

**Breaking** means an existing consumer stops working without a change on its side: a
removed or renamed field, a narrowed type, a newly required request field, or a new enum
value the consumer must handle. An added optional field is not breaking.

---

### 1. NEW ENDPOINT - `POST /v4/booking/hold`

**Milestone** 1 · **Provider** `backend` · **Lands in** `src/openapi/spec/paths/v4/...`
**Auth**: bearer player token. `401` when absent, `403` when the token does not own the booking.
**Called when**: the player taps Checkout, once per attempt.

Request

| Field | Type | Required | Notes |
|---|---|---|---|
| `venueSportId` | string | yes | Opaque. Never parse as a number. |
| `startTime` | string | yes | `HH:mm`, venue local time, 24-hour. Not UTC. |

Response `200`

| Field | Type | Null? | Notes |
|---|---|---|---|
| `data.holdId` | string | no | Opaque; pass back to confirm. |
| `data.expiresAt` | string | no | ISO 8601 with offset. Count down from this, never from a local duration. |
| `data.priceBreakdown[]` | array | no | Empty array when nothing applies - never null. |

```json
{ "data": { "holdId": "h_01J...", "expiresAt": "2026-09-09T14:05:00+07:00", "priceBreakdown": [] } }
```

Errors the consumer branches on

| Status | `code` | Means | Consumer does |
|---|---|---|---|
| 409 | `SLOT_TAKEN` | another player holds it | re-fetch the slot list, show it taken |
| 422 | `VENUE_CLOSED` | outside opening hours | show the venue's hours |

Anything else is a generic error; do not branch on it.

---

### 2. NEW FIELD - `data.cancellationReason` on `GET /v4/booking/{id}`

**Milestone** 1 · **Provider** `backend` · **Breaking** no (additive, optional)

| Field | Type | Null? | Notes |
|---|---|---|---|
| `data.cancellationReason` | string \| null | yes | Null for every status except `cancelled`. Free text - render it, do not switch on it. |

**Every provider path that must return it.** A field added to one path and not another is
the regression this file exists to prevent, so list them and tick them off:

- [ ] the handler itself
- [ ] the `SELECT` / query projection behind it
- [ ] sandbox, mock, or seeded responses
- [ ] every other endpoint returning the same object (a list as well as a detail route)
- [ ] any socket payload carrying that object

Until all of them ship, a consumer must treat a missing key and an explicit `null` alike.

---

### 3. NEW SOCKET EVENT - `booking_held`

**Milestone** 1 · **Provider** `backend`, `src/services/io/booking/` · **Generated spec** none

| Aspect | Value |
|---|---|
| Namespace | player realtime |
| Room | the booking id |
| How the client joins | `handshake.query.bookingId`, a UUID the server validates and rejects if unknown |
| Direction | server -> client |
| Trigger | a hold created by `POST /v4/booking/hold` |
| Envelope | `{ "data": ... }` - every event on this namespace wraps its payload under `data` |

Payload (`data`)

| Field | Type | Null? | Notes |
|---|---|---|---|
| `holdId` | string | no | Same value the HTTP response returned. |
| `expiresAt` | string | no | ISO 8601 with offset. |

Delivery semantics - answer each one; a consumer cannot guess them and will guess wrong:

| Question | Answer |
|---|---|
| Is ordering guaranteed against other events in this room? | |
| Can it arrive more than once? | |
| Is it replayed on reconnect, or only live? | |
| Can it arrive before the HTTP response that caused it? | |
| What should the consumer do if it never arrives? | |

The last two are where realtime consumers actually break: one that treats the event as its
only source of truth hangs forever when it is missed, and one that assumes the event lands
after its own HTTP response races it.

---

## Consumer checklist

- [ ] Every identifier is treated as an opaque string.
- [ ] Every nullable field has a rendered empty state.
- [ ] Every enum has a fallback branch for a value added later.
- [ ] Every listed error `code` has its own consumer behavior.
- [ ] No consumer reads a field this file does not define.

## Open questions

- [ ] {question} - settled by {who or what}
````

An entry that cannot answer a row leaves it blank and adds the question to **Open
Questions**. A guessed answer is worse than an empty cell: the consumer builds on it.

## PRD Artifact Output

When called with a PRD file (`docs/<YYYY-MM-DD>_<task>/prd.md`), write the plan beside it —
`plan.md` for milestone 1, `plan-m<N>.md` after that — using this structure.

Dates come from `date +%F` — run it, never guess. *Created* is written once; *Last updated*
is bumped on every later edit to the plan.

Carry the PRD's deferred **Open Questions** forward: any that block a task must be settled
before that task is written — ask the user in the terminal rather than planning around an
unknown.

````markdown
# Plan: {Feature Name}

**Task**: `<task>`
**Space**: `spaces/<task>/` — repos: backend, sport
**Branch**: `<prefix>/<task>` from `origin/feature/m5.1`
**Working directories**: `spaces/<task>/backend/`, `spaces/<task>/sport/`
**Base commits**: backend `a1b2c3d4e`, sport `f5e6d7c8b`
**Source PRD**: `docs/<YYYY-MM-DD>_<task>/prd.md`
**Selected Milestone**: {N} — {milestone name}
**Complexity**: {Small | Medium | Large}
**Created**: {YYYY-MM-DD} · **Last updated**: {YYYY-MM-DD}

> All paths below are relative to the workspace root and live inside the space.
> `repos/` is read-only and must not appear in this plan.

## Summary
{2-3 sentences}

## Patterns to Mirror
| Category | Source | Pattern |
|---|---|---|
| Naming | `spaces/<task>/<repo>/path:line` | {short description} |
| Errors | `spaces/<task>/<repo>/path:line` | {short description} |
| Tests | `spaces/<task>/<repo>/path:line` | {short description} |

## Files to Change
| File | Action | Why |
|---|---|---|
| `spaces/<task>/<repo>/path` | CREATE / UPDATE / DELETE | {reason} |

## Tasks
### Task 1: {name}
- **Working directory**: `spaces/<task>/{repo}/`
- **Action**: {what to do}
- **Mirror**: {pattern to follow}
- **Validate**: {command that proves correctness, run from the working directory}

## Validation
```bash
# run from inside the space, one block per repo
cd spaces/<task>/<repo> && {project-specific validation command}
```

## Risks
| Risk | Likelihood | Mitigation |
|---|---|---|

## Acceptance
- [ ] All tasks complete
- [ ] Validation passes in every repo the plan touches
- [ ] Patterns mirrored, not reinvented
- [ ] No file outside `spaces/<task>/` was written
- [ ] Every boundary change is in `api-contract.md`, or the Summary says why there is none

## Handoff
<!-- What a space-blind skill or agent needs, and nothing more. -->

**Evidence report**: `docs/<YYYY-MM-DD>_<task>/testing.md`
**API contract**: `docs/<YYYY-MM-DD>_<task>/api-contract.md` — or `none, no boundary change`

| Consumer | Working directory | Base ref |
|---|---|---|
| tdd-workflow | `spaces/<task>/backend/` | — |
| go-reviewer | `spaces/<task>/sport/` | `f5e6d7c8b` |
````

The evidence report is one file for the whole task, not one per repo. `tdd-workflow` is
space-blind and would otherwise write inside the working directory it was given, which
would scatter the evidence across the service repos and put it in their PRs. Hand it that
path explicitly, every time, for every repo: each run adds its own `## <repo>` section to
the same file.

The API contract is handed down the same way and for the same reason. `tdd-workflow` uses
it as the shape the provider's tests must prove, so a boundary change that is not in the
file is a change nothing verifies. Name the path, or say explicitly that this milestone
changes no boundary — silence reads as an omission.

After writing the artifact, report its path and WAIT for confirmation before writing code.

Report the handoff explicitly:

```
Task:  <task>
Space: spaces/<task>/  (backend, sport)  branch <prefix>/<task>

Milestone: {N} — {milestone name}
Plan written: docs/<date>_<task>/plan.md          (plan-m{N}.md for a later milestone)
API contract: docs/<date>_<task>/api-contract.md  ({n} changes: {n} endpoints, {n} fields,
                                                   {n} socket events, {n} breaking)
              (or: none — this milestone changes no boundary)
PRD updated: milestone {N} -> in-progress

Next step (after you confirm): tdd-workflow skill with docs/<date>_<task>/plan.md
  -> pass it the working directory: spaces/<task>/<repo>/
     the evidence report path: docs/<date>_<task>/testing.md
     and the API contract path: docs/<date>_<task>/api-contract.md
     The skill takes the plan's tasks and Validate commands as intent, then proves
     each one through its own RED/GREEN gate. It knows the directory, not the space.
```

## Example Usage

```
User: /plan I need to add real-time notifications when markets resolve

Assistant:
Task binding: no space named `market-resolution-notifications` yet.
Which repos does this touch, and what source branch should it start from?

User: backend,sport from origin/develop

Assistant:
[runs .claude/scripts/space.sh add market-resolution-notifications backend,sport --from origin/develop]

# Implementation Plan: Real-Time Market Resolution Notifications

**Task**: `market-resolution-notifications`
**Space**: `spaces/market-resolution-notifications/` — backend, sport
**Branch**: `<prefix>/market-resolution-notifications` from `origin/develop`

## Requirements Restatement
- Send notifications to users when markets they're watching resolve
- Support multiple notification channels (in-app, email, webhook)
- Ensure notifications are delivered reliably
- Include market outcome and user's position result

## Implementation Phases

### Phase 1: Database Schema
- Add notifications table with columns: id, user_id, market_id, type, status, created_at
- Add user_notification_preferences table for channel preferences
- Create indexes on user_id and market_id for performance

### Phase 2: Notification Service
- Create notification service in spaces/market-resolution-notifications/backend/src/lib/notifications.ts
- Implement notification queue
- Add retry logic for failed deliveries
- Create notification templates

### Phase 3: Integration Points
- Hook into market resolution logic (when status changes to "resolved")
- Query all users with positions in market
- Enqueue notifications for each user

### Phase 4: Frontend Components
- Notification bell in header, notification list modal
- Real-time updates, notification preferences page

## Dependencies
- Redis (for queue)
- Email service

## Risks
- HIGH: Email deliverability (SPF/DKIM required)
- MEDIUM: Performance with 1000+ users per market
- MEDIUM: Notification spam if markets resolve frequently

## Estimated Complexity: MEDIUM

**WAITING FOR CONFIRMATION**: Proceed with this plan? (yes/no/modify)
```

## Important Notes

**CRITICAL**: This command will **NOT** write any code until you explicitly confirm the plan with "yes" or "proceed" or similar affirmative response.

**CRITICAL**: This command never plans a write under `repos/`. Those checkouts are read-only origins; all editing happens in `spaces/<task>/<repo>/`.

If you want changes, respond with:
- "modify: [your changes]"
- "different approach: [alternative]"
- "skip phase 2 and do phase 3 first"

## Integration with Other Commands

The workspace chain is:

```
/space add <task> --from <ref>   ->  spaces/<task>/<repo>/
/plan-prd                        ->  docs/<date>_<task>/prd.md
/plan                            ->  docs/<date>_<task>/plan.md   (plan-m2.md, ... per milestone)
                                 ->  docs/<date>_<task>/api-contract.md   (when a boundary changes)
tdd-workflow skill               ->  implementation, evidence in docs/<date>_<task>/testing.md
/space remove <task>             ->  docs/<date>_<task>/log.md, then teardown
```

Every artifact of a task lands in one directory, `docs/<date>_<task>/`. The date is the day
the PRD was written; find an existing directory with `ls -d docs/*_<task>/` rather than
reconstructing it.

- **Need requirements first?** Use `/plan-prd` — it names the task, opens the space, and writes `docs/<date>_<task>/prd.md`. Then pass that PRD back to `/plan`.
- **Ready to build?** Hand the generated plan to the `tdd-workflow` skill
  (`.claude/skills/tdd-workflow/SKILL.md`) with the plan path as its argument. The skill
  treats the plan as untrusted input: it converts each task into a failing test first, and
  never takes the plan's Validate commands as permission to skip the RED gate.
- **Changing an API, a payload, or a socket event?** The `contract-first` skill governs how
  a boundary moves; `api-contract.md` is where this workspace writes the result down. Both
  are for the shape consumers see — `api-design` is for whether that shape is any good.
- **No space yet?** `/space add <task> [repos] --from <ref>` creates it. `/space list` shows
  what is open; `/space remove <task>` writes the wrap-up log and tears it down.
