---
name: intent-driven-development
description: Turn ambiguous or high-impact product and engineering changes into scoped, verifiable acceptance criteria (AC-001, AC-002…) before or alongside implementation. Use when writing a PRD's Acceptance Criteria, when a user asks to clarify a feature or define acceptance criteria, when de-risking a security/data/migration/integration change, or when reviewing a PRD or issue for unverifiable requirements. Do not trigger for trivial edits, straightforward fixes, active debugging, code review, or implementation requests whose acceptance conditions are already clear unless the user explicitly asks.
metadata:
  origin: ECC
---

# Intent-Driven Development

Produce useful acceptance criteria without turning specification into ceremony. Inspect
available context first, expose genuine ambiguity, and choose verification methods that fit
the work and its risk.

## Where the criteria live

Inside a task, acceptance criteria are part of the requirements, so they live in the task's
`prd.md`, under its **Acceptance Criteria** section — never in a separate brief, and never
inside a service repo. `/plan-prd` writes them there in Phase 4; `/plan` maps each task to
the AC ids it covers, and `tdd-workflow`'s evidence can cite them.

A Full Acceptance Brief (below) needs no second file either: its criteria go in
**Acceptance Criteria**, its risk review in the PRD's **Risks**, its blocking decisions in
**Open Questions**. Outside a task — a user asking to clarify something in chat — return
the criteria in the conversation and write nothing.

## When to Activate

- Writing the Acceptance Criteria section of a PRD
- User asks to clarify a feature, define acceptance criteria, or de-risk a change before implementation
- Request touches security, authentication, persistent data, migrations, external APIs, or compliance
- User wants to prepare a handoff for another team
- Request is ambiguous enough that the expected outcome is not yet observable or testable

Do not activate for trivial edits, straightforward one-line fixes, active debugging sessions,
code review requests, or implementation requests whose acceptance conditions are already clear.

## How It Works

1. **Inspect context first** — reads the repository, docs, schemas, and test infrastructure for technical facts before asking any question, while treating product/business constraints as something only the user or a product artifact can supply
2. **Choose depth** — selects Quick Capture (3-7 criteria, low/moderate risk) or Full Acceptance Brief (security, data, migration, cross-system changes) based on the risk profile
3. **Ask minimally** — only asks questions whose answers cannot be inferred and that materially change scope or behavior
4. **Write observable criteria** — each AC-NNN describes a starting condition, trigger, expected outcome, prohibited side effect, verification method, and priority; no vague words like "correctly" or "securely" without evidence
5. **Proceed or hand off** — for clear requests with no blocking risks, records criteria and continues; for risky changes, presents blockers and waits for confirmation
6. **Handle revision** — if an AC fails mid-implementation due to architectural constraints, marks it `[revised]`, updates scope or verification method, and re-presents only the changed criteria

## Examples

**Quick Capture — "Add CSV export to the dashboard"**

```
Goal: Authenticated users can download dashboard data as a CSV file.
In scope: Export of currently filtered rows; filename includes date.
Out of scope: Scheduled exports, email delivery, Excel format.
Assumptions: Max row count is under 10k; no PII in exported fields.

AC-001: Export generates file with correct headers
- Scenario: authenticated user, at least one data row visible
- Action: click "Export CSV"
- Expected: browser downloads file with columns [id, name, created_at]
- Must not: expose internal fields or rows belonging to other users
- Verification: automated integration test + manual schema spot-check
- Priority: Required
```

**Full Acceptance Brief trigger — "Migrate user auth to OAuth"**

Auth change + external dependency + existing session data → full criteria with a risk
review, blocking decisions on session invalidation strategy, and an explicit rollback AC.

**Existing spec review — user pastes a PRD**

Review it for missing scope boundaries, unverifiable requirements ("the system shall be fast"),
and silent assumptions, then return corrected or supplemental criteria without restarting discovery.

## Operating Rules

1. Inspect the available repository, documentation, issue, design, and test context before
   asking for technical facts that can be discovered locally.
2. Do not infer product or business constraints from code. Business rules, compliance and
   regulatory obligations, contractual SLAs, pricing, data-retention policy, prioritization,
   and target users cannot be read from a repository. Treat them as unknown until the user
   supplies them or an authoritative product artifact (PRD, contract, policy document) states
   them. Record them as assumptions flagged for confirmation, never as discovered facts. The
   repository tells you how the system behaves today, not what the business requires it to do.
3. Ask only questions whose answers are required and cannot be safely inferred. Group short,
   related questions when that saves unnecessary turns.
4. Do not block implementation by default. When the user has asked to implement a sufficiently
   clear change, record key assumptions and acceptance criteria briefly, then proceed.
5. Require explicit user confirmation before proceeding only when an unresolved decision could
   create material security exposure, data loss, irreversible migration, contractual/API
   breakage, meaningful cost, or destructive external action.
6. Write criteria only where *Where the criteria live* says. Never create a branch, commit, or
   write into a service repo to record them.
7. Treat automated tests as evidence, not truth. Prefer automation when reliable and
   proportionate; allow manual UX, accessibility, security, legal, or operational verification
   where automation cannot establish the outcome.
8. Never include real secrets, credentials, tokens, private keys, personal data, or sensitive
   production payloads in acceptance criteria, fixtures, examples, or saved artifacts. Use
   redacted or synthetic values.
9. Do not run destructive tests, migrations, security probes, load tests, paid external calls,
   or operations against production/live data without explicit authorization and an identified
   safe environment.
10. When an acceptance criterion cannot be satisfied due to an architectural, platform, or
   external constraint discovered during implementation, do not silently drop or work around it.
   Edit the criterion in `prd.md` — mark it `[revised]`, state the constraint, adjust scope or
   verification method, bump *Last updated* — and re-present only the changed criteria to the
   user before continuing. Require explicit confirmation only if the revision changes a
   blocking decision or materially reduces safety or correctness guarantees.

## Choose The Depth

Use the smallest useful output.

### Quick Capture

Use for a clear but non-trivial change with low or moderate risk. Produce:

- Goal
- In scope / out of scope
- Assumptions
- 3-7 acceptance criteria with verification methods
- Blocking questions, if any

In a PRD, goal and scope already have sections — write only the criteria.

### Full Acceptance Brief

Use for ambiguous, cross-system, security-sensitive, data-changing, migration, compliance,
or high-cost changes. Produce the full criteria, a risk review, and a verification plan, and
request confirmation for unresolved blocking decisions before risky implementation.

### Existing Specification Review

When the user already supplied a PRD, issue, plan, or acceptance criteria:

1. Review it instead of restarting discovery.
2. Identify missing scope boundaries, unsafe assumptions, contradictions, and unverifiable
   requirements.
3. Return corrected or supplemental criteria.

## Discovering context

Extract or ask for the observable outcome, the actors affected, the main failure consequence,
and only the risk dimensions that actually apply: security/privacy, persistent data,
compatibility/API, migration, external dependencies, cost, concurrency, performance,
usability/accessibility. Avoid generic questions about irrelevant risks.

When code is available, inspect only what is needed: existing behavior and directly related
files, the repo's conventions and contracts, data schemas or migration history, and the test
infrastructure that will verify the criteria. Record discovered facts separately from
user-provided assumptions.

The repository reveals technical facts — how the system behaves today, its conventions, and
its contracts. It does not reveal product or business constraints. Never reconstruct those
from code or naming; list them as assumptions to confirm until the user supplies them.

## Writing a criterion

Use `AC-001`, `AC-002`, and so on — numbering is per task and never reused, so a later
milestone continues the sequence. Each criterion describes observable behavior and an
appropriate verification method; criteria and tests are not required to map one-to-one.

For each applicable criterion include:

- Scenario or starting condition.
- Action or trigger.
- Expected observable behavior.
- Prohibited side effect when meaningful.
- Verification method: automated test, integration check, manual UX review, accessibility
  check, security review, operational check, or stakeholder acceptance.
- Environment/safety constraint when verification could affect data, services, cost, or secrets.
- Priority: Required, Important, or Optional.

Do not use words such as "correctly", "securely", "fast", "intuitive", or "robust" without
defining observable evidence or recording them as a human-review judgment.

### Cover only relevant boundaries

| Category | Include when | Typical evidence |
| --- | --- | --- |
| Happy path | New or changed user-visible behavior | Successful workflow or state transition |
| Validation | The change accepts input | Rejected malformed or boundary value without mutation |
| Authorization/privacy | Data or actions have access boundaries | Denied access and no sensitive disclosure |
| Persistence/migration | Stored data or schemas change | Backward read, migration, rollback or backup behavior |
| Compatibility | Public APIs, files, events, or clients may break | Existing contract or fixture remains valid |
| Failure recovery | Network, service, or asynchronous failure exists | No partial state or clear retry/degraded behavior |
| Idempotency/concurrency | Repeats or simultaneous writes are plausible | No duplicate side effect or invalid final state |
| Performance | A user or service threshold matters | Defined measurement conditions and threshold |
| UX/accessibility | A person interacts with the result | Keyboard, feedback, error recovery, visual/manual review |

### Criterion template

```markdown
### AC-001: <observable behavior>
- **Scenario:** <starting condition>
- **Action:** <single trigger>
- **Expected:** <observable result>
- **Must not:** <prohibited side effect, if applicable>
- **Verification:** <method and intended evidence>
- **Environment/safety:** <constraints, if applicable>
- **Priority:** Required | Important | Optional
```

For a Full Acceptance Brief, the risk review uses the PRD's **Risks** table; add a row per
area that applies (security/privacy, persistent data/migration, external effects/cost,
compatibility/API, UX/accessibility) with the handling it requires.

## Pass/Fail Examples

**A failing acceptance criterion**

```
AC-001: The export works correctly and is secure.
```

Fails — "works correctly" and "secure" are not observable, there is no scenario, trigger,
expected result, or verification method, and nothing states what must not happen.

**A passing acceptance criterion**

```
AC-001: Export generates file with correct headers
- Scenario: authenticated user, at least one data row visible
- Action: click "Export CSV"
- Expected: browser downloads file with columns [id, name, created_at]
- Must not: expose internal fields or rows belonging to other users
- Verification: automated integration test + manual schema spot-check
- Priority: Required
```

Passes — a concrete observable outcome, a prohibited side effect, and a named verification
method. Two people would agree on whether it was met.

**A failing context entry**

```
Discovered facts: Users on the free tier are limited to 100 exports per month.
```

Fails — a per-tier limit is a business rule. It must not be presented as discovered from
code; it is supplied by the user, or listed as an assumption to confirm.

### Rubric

The criteria pass only if every answer is "yes".

- [ ] Does every Required criterion have a scenario, an observable expected result, and a named verification method?
- [ ] Are all vague terms ("correctly", "secure", "fast", "robust") either replaced with observable evidence or marked as human judgment?
- [ ] Are product/business constraints listed as supplied/assumed, with none silently inferred from code?
- [ ] Is scope explicit, with out-of-scope items named?
- [ ] Are blocking decisions limited to choices that actually affect safety or correctness, not preferences?
- [ ] Was no secret or production-sensitive value copied into the criteria?
