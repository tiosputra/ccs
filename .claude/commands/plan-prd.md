---
description: "Write a PRD for a task, then on your confirmation create its space, implement it test-first, review it, and stop for approval to open the PR."
argument-hint: "<task idea> from branch <source-ref>"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Skill, Agent
---

# PRD Command

Produces a **Product Requirements Document** — the requirements-phase artifact of the SDLC. Captures *what* must be true for success and *why*, and stops before *how*. Implementation decomposition is delegated to `/plan`.

**Input**: `$ARGUMENTS` — the task idea, optionally followed by the source branch.

```
/plan-prd new-feature from branch origin/feature/m5.1
/plan-prd fix promo codes expiring early from origin/develop
/plan-prd offline sync            <- no source branch: this command must ask
```

Parse it as: everything before `from branch` / `from` / `--from` is the **idea**; what
follows is the **source branch**. The idea also names the task, its space, its branch, and
every downstream artifact.

## Scope of this command

This command owns the **whole run**, but the PRD it writes first is requirements-only.

| The PRD captures | The PRD does NOT capture |
|---|---|
| The problem, users, and evidence | The architecture |
| Success criteria and scope | File paths or code patterns |
| The space it proposes to create | An implementation task breakdown |
| Open questions and risks | Anything `/plan` is for |

If you find yourself writing implementation detail *into the PRD*, cut it — it belongs in
the plan, which this command generates later, after Gate 1.

**Anti-fluff rule**: When information is missing, write `TBD — needs validation via {method}`. Never invent plausible-sounding requirements.

## Workflow

Eight phases and **exactly two stops**. Phases 1–3 gather requirements a question-set at a
time, and Phase 3.5 clears every question the user can answer before anything is written.
Phase 5 is Gate 1 and Phase 7 is Gate 2 — those are the only places you hand control
back. Between Gate 1 and Gate 2 the run is continuous: do not stop to ask permission for
each step, because Gate 1 already approved the build.

### Phase 0 — PROPOSE THE TASK

Settle the binding on paper. **Do not create anything yet** — the space is created after
Gate 1, so the user can read the PRD and correct the plan before any branch exists.

Derive a kebab-case `<task>` name from the idea (short, 2–4 words: `offline-sync`,
`hotfix-username`). Then check what already exists:

```bash
.claude/scripts/space.sh list
ls -d docs/*/ 2>/dev/null
ls -d docs/*_<task>/ 2>/dev/null   # this task's directory, whatever day it opened
```

- If a space named `<task>` already exists, reuse it — do not create a second one, and do
  not rename the task. Say so in the PRD.
- If a directory for `<task>` already exists, read the `prd.md` in it and offer to
  continue that task rather than overwriting. Never open a second directory for a task
  that already has one, and never re-date the one it has.

**The source branch is required and never guessed.** If `$ARGUMENTS` contained one, use it
and confirm it back. If it did not, ask — and ask again rather than defaulting to
`origin/main`. It decides what the work is built on; getting it wrong means a rebase later.

> Which branch should this start from? (e.g. `origin/main`, `origin/develop`,
> `origin/feature/m5.1`, or per-repo `backend=origin/release-2`)

**Repos** you may propose rather than ask: infer from the framing answers which services
the change touches, and state the proposal in the PRD. Gate 1 is where the user corrects
it. Only ask outright if the scope leaves it genuinely unclear — and then fold the question
into the Phase 1 set rather than spending a separate turn on it.

### Phase 1 — FRAME

If `$ARGUMENTS` is empty, ask:

> What do you want to build? One or two sentences.

If provided, restate in one sentence and ask:

> I understand: *{restated}*. Correct, or should I adjust?

Then ask the framing questions in a single set:

> 1. **Who** has this problem? (specific role or segment)
> 2. **What** is the observable pain? (describe behavior, not assumed needs)
> 3. **Why** can't they solve it with what exists today?
> 4. **Why now?** — what changed that makes this worth doing?

Wait for the user. Do not proceed without answers (or explicit "skip").

### Phase 2 — GROUND

Ask for evidence. This is the shortest phase and the most load-bearing:

> What evidence do you have that this problem is real and worth solving? (user quotes, support tickets, metrics, observed behavior, failed workarounds — anything concrete)

If the user has none, record the PRD's Evidence section as `Assumption — needs validation via {user research | analytics | prototype}`. This keeps the PRD honest.

### Phase 3 — DECIDE

Scope and hypothesis in a single set:

> 1. **Hypothesis** — Complete: *We believe **{capability}** will **{solve problem}** for **{users}**. We'll know we're right when **{measurable outcome}**.*
> 2. **MVP** — The minimum needed to test the hypothesis?
> 3. **Out of scope** — What are you explicitly **not** building (even if users ask)?
> 4. **Open questions** — Uncertainties that could change the approach?

Wait for responses.

### Phase 3.5 — RESOLVE (ask, don't park)

The user is *right here*. Every question you can answer by asking them, ask now — in the
terminal, before the PRD is written. A question parked in the PRD costs a round trip the
interview could have absorbed.

After drafting the PRD in your head, list every uncertainty you are about to write into
**Open Questions** and sort each one:

| Sort | Test | Where it goes |
|---|---|---|
| **Ask now** | The user can answer it from knowledge or preference in one sentence | Ask in this phase; the answer goes into the body of the PRD as a decision |
| **Defer** | Answering needs data, code you have not read, a third party, or a spike | Stays in **Open Questions**, with the method that will settle it |

Anything you would write as *"Proposal: X. Needs confirmation."* is an **ask now** — that
phrasing is the tell that you have a question and the user has the answer.

Read the code first. A question you could settle by opening the file is not the user's
question; go read the file. `/plan-prd` may read anything under `repos/` — reading is
always allowed there, writing never is.

Ask the survivors in one batch, not one per turn. Then write the PRD with those answers
baked in as decisions, and let **Open Questions** hold only what genuinely could not be
settled today.

If a deferred question could change the MVP, say so at Gate 1 — the user may want to
settle it before any branch exists.

### Phase 4 — WRITE THE PRD

```bash
date +%F                              # never guess or reuse a date from memory
mkdir -p docs/<YYYY-MM-DD>_<task>
```

**Output path**: `docs/<YYYY-MM-DD>_<task>/prd.md`, where the date is today's `date +%F`
and `<task>` is the kebab-case task name — e.g.
`docs/2026-08-28_offline-sync/prd.md`. This directory is where every later artifact of the
task goes too: `plan.md`, `api-contract.md`, `testing.md`, `log.md`. Creating it is the one write this phase
makes; no space, no branch, no code.

The date in the directory name is the day the task **opened** and never changes afterwards.
A PRD edited later keeps its directory; only the *Last updated* line moves. Never re-date
the directory — the plans, the evidence, the log and the PR all point into it.

Because the date prefix is not derivable from the task name, always **glob** for an
existing directory (`ls -d docs/*_<task>/`) rather than guessing the path.

Both dates come from `date +%F` in `YYYY-MM-DD`. *Created* is written once and never
changes; *Last updated* is bumped every time the file is edited afterwards — at Gate 1
corrections, when the space is created, and when a milestone flips to complete.

#### PRD Template

```markdown
# {Product / Feature Name}

*Created {YYYY-MM-DD} · Last updated {YYYY-MM-DD}*

## Space to create
<!-- PROPOSED, not created. Nothing exists yet - Gate 1 is where you approve this. -->

| Field | Value |
|---|---|
| Task | `<task>` |
| Space | `spaces/<task>/` |
| Repos | backend, sport |
| New branch | `<prefix>/<task>` (same name in every repo) |
| Source branch | `origin/feature/m5.1` |
| Working directories | `spaces/<task>/backend/`, `spaces/<task>/sport/` |
| PR base | `feature/m5.1` — one PR per repo |
| Command that will create it | `.claude/scripts/space.sh add <task> backend,sport --from origin/feature/m5.1` |

Say if the repos or the source branch are wrong — this is the moment to change them,
before any branch exists.

## Problem
{2-3 sentences: who has what problem, and what's the cost of leaving it unsolved?}

## Evidence
- {User quote, data point, or observation}
- {OR: "Assumption — needs validation via {method}"}

## Users
- **Primary**: {role, context, what triggers the need}
- **Not for**: {who this explicitly excludes}

## Hypothesis
We believe **{capability}** will **{solve problem}** for **{users}**.
We'll know we're right when **{measurable outcome}**.

## Success Metrics
| Metric | Target | How measured |
|---|---|---|
| {primary} | {number} | {method} |

## Scope
**MVP** — {the minimum to test the hypothesis}

**Out of scope**
- {item} — {why deferred}

## Delivery Milestones
<!-- Business outcomes, not engineering tasks. Each becomes its own plan. -->
<!-- Status: pending | in-progress | complete -->

| # | Milestone | Outcome | Repos | Status | Plan |
|---|---|---|---|---|---|
| 1 | {name} | {user-visible change} | backend | pending | — |
| 2 | {name} | {user-visible change} | sport | pending | — |

## Open Questions
<!-- Only what could NOT be settled in Phase 3.5. Anything the user could have answered -->
<!-- belongs in the body as a decision, not here. Each one names how it gets settled. -->
- [ ] {question} — settled by {reading X | a spike | analytics | asking {who}}

## Risks
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|

---
*Status: AWAITING APPROVAL — no space created yet. Confirm to build. ({YYYY-MM-DD})*
```

### Phase 5 — GATE 1: stop and wait

Report, then **stop**. Do not create the space. Do not write code. The user asked for this
pause so they can open the file and read it.

```
PRD written: docs/<YYYY-MM-DD>_<task>/prd.md

Proposed space
  Task    <task>
  Repos   backend, sport
  Branch  <prefix>/<task>
  From    origin/feature/m5.1
  Nothing created yet.

Problem:    {one line}
Hypothesis: {one line}
MVP:        {one line}
Milestones: {count}

Validation status
  Problem  {validated | assumption}
  Users    {concrete | generic — refine}
  Metrics  {defined | TBD}

Open questions: {count} deferred ({count} resolved in the interview)

Read it, then say the word and I'll create the space, implement milestone 1 test-first,
and run code review. I'll stop again before opening any PR.
```

Anything other than approval — a correction, a new source branch, a different repo list —
means edit the PRD and stop again. Only an explicit yes moves to Phase 6.

### Phase 6 — BUILD (only after Gate 1)

Now run straight through. No further permission prompts; Gate 1 covered all of this.

1. **Create the space** with the exact command the PRD named:

   ```bash
   .claude/scripts/space.sh add <task> <repos> --from <source-branch>
   ```

   Report which worktrees were created, the branch, and the base commit per repo. If a repo
   fails, say why and stop — do not retry with a different base ref.

   Then update the PRD: replace *Space to create* with the real values, change the
   status line to `Status: IN PROGRESS`, and bump *Last updated* to today's `date +%F`.

2. **Plan the next pending milestone** — follow `/plan`'s PRD artifact mode. Write the plan
   beside the PRD, in the same directory: `plan.md` for milestone 1, `plan-m<N>.md` after
   that, with working directories and base commits filled in. Flip that milestone's row to
   `in-progress`.

   If the milestone changes anything a consumer can observe — a new endpoint, a new or
   changed response field, a new socket event, a new error to branch on — `/plan` also
   writes `api-contract.md` in that directory, per its **API Contract** section. That file
   is read by the frontend and mobile teams, so it is written now, while the provider is
   still hypothetical, rather than reverse-engineered from the finished handler. One file
   per task: a later milestone appends its entries to the same one.

3. **Implement it** with the `tdd-workflow` skill, once per repo the milestone touches.
   Hand it four things: the plan path, the working directory `spaces/<task>/<repo>/`, the
   evidence report path `docs/<YYYY-MM-DD>_<task>/testing.md`, and the API contract
   `docs/<YYYY-MM-DD>_<task>/api-contract.md` when the milestone wrote one. The skill is space-blind
   — give it directories and paths, never a task name — and it writes its evidence wherever
   it is told, so passing that path is what keeps the whole task's evidence in one file
   instead of scattering a copy into each service repo. Every repo appends its own
   `## <repo>` section to that same file.

4. **Review it.** Dispatch by language, giving each reviewer the working directory and the
   base commit from the PRD:
   - Go (`sport`, `player`) -> `go-reviewer`
   - TypeScript (`backend`) -> `typescript-reviewer`

   Fix anything the review rates CRITICAL or HIGH, then re-run the affected tests. Report
   MEDIUM findings without necessarily fixing them; that is the user's call at Gate 2.

5. **Mark the milestone** `complete` in the PRD.

### Phase 7 — GATE 2: done, ask about the PR

Report and **stop**. Do not stage, commit, push, or open a PR until the user says so.

```
Done: <task> — milestone {N}, {milestone name}

  {repo}   {n} files changed   tests {pass/total}   review {clean | n findings}
  {repo}   {n} files changed   tests {pass/total}   review {clean | n findings}

Evidence:  docs/<date>_<task>/testing.md   ({n} repo sections)
Plan:      docs/<date>_<task>/plan.md      (plan-m{N}.md for a later milestone)
Contract:  docs/<date>_<task>/api-contract.md   ({n} changes, {n} breaking — or "none")
Uncommitted in: spaces/<task>/<repo>/   (nothing committed yet)

Review findings left open:
  - {MEDIUM finding, or "none"}

Ready to open the PR? That will stage, commit, push <prefix>/<task>, and open one PR
per repo against {source branch}. Or say what to change first.
```

On approval, run `/pr` — it does the staging, committing, pushing, and PR creation, one PR
per repo with changes. Pass it the base branch from the PRD if it differs from the default.

If milestones remain, offer the next one after the PR is open.

## Integration

```
/plan-prd <idea> from branch <ref>
      |         writes docs/<date>_<task>/prd.md   <- nothing else created yet
   [GATE 1]     you read it and confirm
      |         space.sh add -> /plan (+ api-contract.md) -> tdd-workflow -> reviewer agents
   [GATE 2]     you confirm it is ready
      |
    /pr         stage, commit, push, open one PR per repo
```

- `/space` — create or tear down a space by hand, outside this flow.
- `/plan` — plan a later milestone of an existing PRD on its own.
- `tdd-workflow`, `go-reviewer`, `typescript-reviewer` — space-blind; they are handed a
  working directory and a base ref, never a task name.
- `/pr` — the only thing that commits.

## Success criteria

- **SOURCE_BRANCH_EXPLICIT**: the source branch came from the invocation or from asking, never from a default.
- **NOTHING_CREATED_BEFORE_GATE_1**: no space, no branch, no code — only the PRD file.
- **TWO_STOPS_EXACTLY**: the run pauses at Gate 1 and Gate 2, and nowhere else.
- **PROBLEM_CLEAR**: problem is specific and evidenced (or flagged as assumption).
- **USER_CONCRETE**: primary user is a specific role, not "users".
- **HYPOTHESIS_TESTABLE**: measurable outcome included.
- **SCOPE_BOUNDED**: explicit MVP and explicit out-of-scope.
- **QUESTIONS_ASKED_NOT_PARKED**: every uncertainty the user could answer was asked in the terminal before the PRD was written; Open Questions holds only what needs data, a spike, or a third party — each with the method that settles it.
- **CONTRACT_BEFORE_IMPLEMENTATION**: a milestone that changes an endpoint, a response field, a socket event, or an error a consumer branches on has `api-contract.md` written before the implementation, not after — and a milestone that changes no boundary says so rather than leaving it ambiguous.
- **ONE_TASK_ONE_DIRECTORY**: every artifact of the task — PRD, plans, API contract, evidence, log — is written inside `docs/<YYYY-MM-DD>_<task>/`, and nothing of this task is written anywhere else.
- **PRD_DIRECTORY_DATED**: the directory is `docs/<YYYY-MM-DD>_<task>/` with the date from `date +%F`; an existing one is found by globbing `docs/*_<task>/`, never by guessing a date, and never re-dated.
- **PRD_DATED**: the PRD carries *Created* and *Last updated* dates in `YYYY-MM-DD`, taken from `date +%F`, and *Last updated* is bumped on every later edit.
- **NO_REPOS_PATHS**: no path under `repos/` appears anywhere in the PRD.
- **NOTHING_COMMITTED_BEFORE_GATE_2**: the build leaves work uncommitted; `/pr` commits it.
