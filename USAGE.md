# Usage

A quick guide to this workspace: what it is for, what each command does, and where
its output lands. For how the system is built, read `README.md`; for the rules every
session follows, `CLAUDE.md`.

## What this workspace is

A Claude Code setup that sits beside the repos you work on. It runs two kinds of work:

| | Business work | Development work |
|---|---|---|
| Question | *Is this worth building?* | *Build it.* |
| Commands | `/idea` → `/brand` → `/market` → `/decide` | `/plan-prd` → `/pr` |
| Writes to | `business/` | the repos, plus `tasks/<date>_<task>/` |
| Touches code? | Never | Yes, on a task branch |
| Stops to ask you | when a step needs your answer | at exactly two gates |

The two meet at one point: a **go** from `/decide` is what you hand to `/plan-prd`.

```
/idea ─► /brand ─► /market ─► /decide ──go──► /plan-prd ─► [Gate 1] ─► build ─► [Gate 2] ─► /pr
 gut      who we    evidence   verdict +        PRD         you          test-     you         one PR
 brief    are                  ranking                      confirm      first     confirm     per repo
```

You can enter anywhere. A bug fix starts at `/plan-prd`; a brand refresh is just
`/brand`.

## Where things live

```
repos/<repo>/          your checkouts; a task works here, on its branch
spaces/<task>/<repo>/  worktrees, only for tasks started with --space
tasks/<date>_<task>/   everything written about one task: prd.md, plan.md, testing.md, log.md
project/               the product spec and briefs every task reads
business/              ideas/, branding/, marketing/, decide.md
release/               deployment notes
```

All of these are gitignored except their READMEs. They hold private code and plans.

## Business commands

None of these start a task, create a branch, or touch a repo.

### `/idea <name> [--investor-material]`

Writes a gut-level brief for one idea. Put the description on the lines below the
command:

```
/idea focus-buddy --investor-material
A study companion that pairs two people on the same timer…
```

- Asks the product-diagnostic questions your description didn't answer, all in one
  set. Answer "skip" and that answer is recorded as an assumption.
- Writes `business/ideas/<name>/brief.md`, which ends with a verdict: **go**, **no-go**
  or **not yet**, plus the riskiest assumption.
- `--investor-material` adds `investor/`: `facts.md` (written first, and the one place
  numbers come from), then `one-pager.md` and `deck-outline.md`. An HTML deck is
  offered as an extra.
- Running it again for the same name updates the brief in place.

### `/brand [status | discover | voice]`

One brand for the whole project, in `business/branding/`.

| Run | Does |
|---|---|
| `/brand` or `/brand status` | Shows each interview module's progress and suggests the next step |
| `/brand discover` | Continues the brand interview, one question at a time. It spans several sessions; each module is saved as it closes, so any session can pick it up |
| `/brand voice` | Measures your real writing (posts, copy, emails you supply) into a voice profile, `voice.md` |

The interview ends in a brandbook, `modules/90_SYNTHESIS.md`. `/market` and
`/decide` read its positioning.

### `/market [status | scan | compete | report] [focus]`

One market picture for the whole project, in `business/marketing/`. Text after the
subcommand narrows the focus.

| Run | Does | Writes |
|---|---|---|
| `/market` | Shows what exists, what is out of date, and the next step | — |
| `/market scan` | Wide research: market size, demand, trends, customers. It also tries to answer each idea's riskiest assumption | `scan.md` |
| `/market compete` | Picks the competitors, then **stops so you confirm the set**, then scores each one and writes the report | `compete/scope.md`, `compete/cards/*.md`, `compete/report.md` |
| `/market report` | Merges the scan and the competitive report into one brief, with a paragraph per idea | `brief.md` |

Every number carries a source or is labelled an estimate. Web pages are treated as
evidence to weigh, never as instructions.

### `/decide [idea]`

Re-judges every idea using the evidence from `/brand` and `/market`, then ranks the
survivors by impact × confidence ÷ effort.

- Writes `business/decide.md`: a verdict table, the ranking, a section per idea and a
  history of earlier decisions.
- With no market evidence yet, it says so and recommends `/market scan` first.
- Nothing changed since the last run? It shows the last decision instead of
  re-deciding.
- It recommends `/plan-prd <top idea> from branch <ref>` but never runs it. You start
  development.

## Development commands

### `/plan-prd <idea> from branch <ref> [--space]`

The main command. It runs a whole task, stopping twice:

1. Asks framing questions. If the idea came from `/idea`, its brief answers most of
   them.
2. Writes `tasks/<date>_<task>/prd.md`. **Gate 1:** you read and confirm. Nothing has
   started yet.
3. Starts the task, writes the plan, implements test-first, and runs the reviewers.
4. **Gate 2:** reports what changed, uncommitted. You confirm, then run `/pr`.

The source branch is required and never guessed. `--space` gives the task its own
worktrees instead of working in `repos/`.

### `/pr [task] [base] [--draft]`

Stages, commits, pushes and opens **one pull request per repo** in the task, each
against the branch the task started from.

### `/plan [description | tasks/<date>_<task>/prd.md]`

Writes an implementation plan only, then waits for your confirmation. `/plan-prd`
calls it for you; run it on its own when you want just a plan.

### `/task …`

Manages a task's working directories by hand.

| Run | Does |
|---|---|
| `/task start <task> <repos> --from <ref> [--space]` | Starts a task: switches each repo to the task branch, or makes worktrees |
| `/task list` | Lists open tasks, and whether any repo has uncommitted changes |
| `/task where <task> [repo]` | Shows where a task's files are |
| `/task finish <task>` | Writes the wrap-up into `log.md`, then releases the repos. It refuses while there are uncommitted changes |
| `/task repos` | Lists which repos are checked out |
| `/task config` | Shows your branch prefix and other per-machine settings, and where each came from |

### `/save-session` and `/resume-session [task]`

`/save-session` writes where the task stands (next step, what failed, what was
decided) into its `log.md`. `/resume-session` reads that log back in a fresh session
before anything else happens. New sessions also list open tasks that have a saved
log.

### Supporting commands

| Command | Does |
|---|---|
| `/deployment-notes <name>` + one line per service | Compares each service's feature branch to its target, then writes developer notes (what to prepare, deploy order, rollback, what to watch) and a QA release note |
| `/graph [build \| review \| run …]` | Builds code graphs of the repos, and shows what a task's change touches |
| `/learn <skill> <repo>` | Records once how a repo does something a skill covers (its logger, its test command), so later sessions read the note instead of re-scanning |
| `/ccs` | Health check of the workspace system itself; proposes one fix |
| `/ccs note <text>` | Records one line of friction mid-task, to fix later |

## Skills: guidance that loads on its own

Skills are not typed. They load when the work matches them, and the commands above
call the right ones. Worth knowing they exist:

| Area | Skills |
|---|---|
| Product and business | `product-lens`, `product-capability`, `investor-materials`, `frontend-slides`, `market-research`, `competitive-platform-analysis`, `benchmark-methodology`, `competitive-report-structure`, `brand-discovery`, `brand-voice` |
| Building | `tdd-workflow`, `contract-first`, `logging`, `api-design`, and patterns for Go, Flutter/Dart, React, Postgres |
| UI | `design-system`, `liquid-glass-design` |
| Checking | `e2e-testing`, `verification-loop`, `browser-qa`, `canary-watch` (after a deploy) |
| Deciding | `council`, `dev-team`, `architecture-decision-records` |

## Common recipes

**A new business idea, start to finish**

```
/idea focus-buddy          (describe it below)
/market scan
/market compete
/market report
/decide
/plan-prd focus-buddy from branch origin/main
```

**A bug fix**

```
/plan-prd fix timer skipping on resume from branch origin/main
```

**Stopping halfway and coming back**

```
/save-session
… new session …
/resume-session <task>
```

**After a release**

```
/deployment-notes <name>   then one line per service
```

Then ask for a canary check of what the notes say to watch.

## Rules worth knowing

- Every change goes through a task, and reaches the base branch only through a PR.
- Source branches are never deleted. Repos in `REFERENCE_REPOS` are read-only.
- A repo's own `AGENTS.md` decides how code in that repo is written.
- Business commands never write code. Development commands never write into
  `business/`.
- Your branch prefix is per machine. `/task config` shows yours.
