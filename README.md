Inspired by : https://github.com/affaan-m


# ccs

A Claude Code workspace for working on one or more service repos, task by task.

Clone it next to the repos you work on, put those repos in `repos/`, and every
task gets the same flow: a PRD you confirm, a plan, a test-first build, a code
review you confirm, and one pull request per repo. Nothing in it names a
project, so the same clone pattern works for a single small service and for a
dozen that change together.

A task works **in place** by default — in each repo's own checkout, switched to
the task branch — which is all a simple project needs. When a task needs
isolation, start it with `--space` and it gets its own git worktrees instead, so
several tasks can be open on the same repo at once: a hotfix, a feature, an
experiment, with no stashing and no `git checkout` whiplash between them.

## Layout

```
<workspace>/
├── repos/                  your checkouts — cloned here, one per repo
│   └── <repo>/                 in place, a task works right here on its branch
│       └── AGENTS.md               that team's rules for that repo, where it has one
│
├── spaces/                 worktrees for tasks started with --space
│   └── <task>/
│       └── <repo>/             -> repos/<repo>  on <prefix>/<task>
│
├── docs/                   one directory per task - everything written about it
│   └── 2026-08-28_add-label/
│       ├── prd.md              requirements, confirmed at Gate 1
│       ├── plan.md             milestone 1 (plan-m2.md, plan-m3.md follow)
│       ├── api-contract.md     what consumers see change - read by the consumer teams
│       ├── testing.md          RED/GREEN evidence, one section per repo
│       ├── log.md              wrap-up, written just before the task finishes
│       └── <anything>          supporting files - .sql, .csv, examples, notes
│
├── release/                deployment runbooks, one per release
│
├── .claude/
│   ├── commands/           /plan-prd, /plan, /task, /pr, /ccs, /learn, /graph
│   ├── skills/             tdd-workflow, logging, ccs-conventions, the pattern skills
│   ├── learned/            per-repo facts a skill learned - gitignored, see /learn
│   ├── state/              which tasks are open on this machine - gitignored
│   ├── agents/             the reviewers, tdd-guide, build resolvers run by hand
│   ├── ccs-notes.md        friction found while running tasks
│   └── scripts/
│       ├── task.sh         starts, locates, reports on and finishes tasks
│       ├── tasklib.sh      where a task's work lives - the one place that knows
│       ├── ccs.sh          checks the workspace system itself
│       ├── learn.sh        which learned facts exist, and whether they are stale
│       ├── graph.sh        code-review-graph graphs, kept outside the repos they describe
│       └── guard.sh        PreToolUse hook - never deletes a source branch; reference repos read-only
```

`repos/<repo>` is writable, like a space's worktree - files and git alike. What
the guard refuses is deleting or renaming a source branch (a task's base, the branch
a task returns a checkout to, `TASK_DEFAULT_BASE`, the remote's default branch), in
`repos/` or a space. Repos listed in `REFERENCE_REPOS` are read-only everywhere.

A repo that carries an `AGENTS.md` carries its team's rules for that codebase,
and those rules outrank this workspace's skills and conventions wherever the two
disagree — see `CLAUDE.md`. What they do not move is where work happens: the
task's working directories, the two gates, the task's documents, and `/pr` are
the same for every repo.

## Repos

The roster is whatever is on disk. Any git checkout directly under `repos/` is
a repo, and **its directory name is its alias**. That is the whole rule, and it
is why no list of repos appears in this file — a list here would be one more
thing to update, and the first thing to go stale.

```
/task repos
```

prints the current roster: each checkout, its remote, and any open task using
it. Add a repo by cloning it into `repos/`. Nothing else needs changing and no
doc needs editing.

A longer service name resolves by prefix, so `api-service` finds `api`.
Wherever a command takes a repo list, it takes those aliases, comma-separated.

**Omitting the repo list means every workable checkout in `repos/`.** Name the
repos the task actually needs.

### Reference-only repos

Not every checkout is one you work in. A mobile client, a partner service, a
repo you cloned only to read its contracts — those are reference material, and
an agent should never edit them, in `repos/` or in a space.

List them in `.env`, comma-separated, by their alias:

```
REFERENCE_REPOS=mobile,partner
```

From then on `/task repos` marks them `reference-only`, `/task start` leaves them
out of the default set and refuses if you name one, and the guard hook blocks
every write to them in `repos/` **and** in any space. Reading, grepping and
`git log` stay untouched — that is what the repo is there for.

The list is per machine, like the branch prefix, so no tracked file names it.
`/task config` prints what yours resolved to.

## The task flow

One command runs a task end to end, stopping twice to ask you:

```
/plan-prd add promo codes from branch origin/feature/m5.1
      |
      |   writes docs/YYYY-MM-DD_add-promo-codes/prd.md
      |   the PRD proposes the task: repos, isolation, source branch, new branch, PR base
      |   nothing is started yet
      |
 [GATE 1]  you read the PRD and confirm - or correct the repos / isolation / source branch
      |
      |   task.sh start           -> each repo's working directory, on <prefix>/add-promo-codes
      |   /plan                   -> docs/<date>_add-promo-codes/plan.md
      |   tdd-workflow            -> implementation, RED/GREEN, evidence report
      |   reviewers by language   -> CRITICAL and HIGH findings fixed
      |
 [GATE 2]  it reports what changed and stops, uncommitted
      |
    /pr     stage, commit, push <prefix>/add-promo-codes, open one PR per repo
```

Those two stops are the whole point: you read the requirements before a branch
exists, and you see the finished work before anything is pushed.

`/plan`, `/task`, and `/pr` all still work standalone if you want a single step.

## In place or in a space

| | In place (default) | Space (`--space`) |
|---|---|---|
| Working directory | `repos/<repo>`, switched to the task branch | `spaces/<task>/<repo>`, a git worktree |
| Parallel tasks on one repo | no — one in-place task holds a repo at a time | yes |
| Env files | already there | copied from `repos/<repo>` |
| Finish | the checkout goes back to the branch it was on | the worktree is removed |

Both kinds can be open at once. `/task start` refuses an in-place task on a repo
that is dirty or held by another task, and says to use `--space` — it never
changes a task's layout on its own. `TASK_DEFAULT_ISOLATION` in `.env` sets which
one a task gets when neither flag is given.

Nothing needs to know which one a task uses: every command asks
`task.sh where <task> <repo>` for the directory.

## Everyday use

Everything task-related goes through one command:
`/task start | finish | list | where | repos | config`.

Start a task in place, in two repos, off a release branch:

```
/task start hotfix-payment api,worker --from origin/release-2
```

Start one in its own worktrees:

```
/task start rework-booking api --from origin/develop --space
```

See what's open, and whether anything is dirty:

```
/task list
```

Find where a task's work is:

```
/task where hotfix-payment api
```

See which repos are checked out at all, and what your settings resolve to:

```
/task repos
/task config
```

Finish up. This writes `docs/<date>_<task>/log.md` **before** anything moves, so
the summary is captured while the diffs are still there:

```
/task finish hotfix-payment
```

`finish` refuses while a repo has uncommitted changes, and with
`--delete-branch` also while it has commits that reached no remote. Push or stash
first, or pass `--force` to discard on purpose. An in-place task can be finished
as soon as its PRs are open — the pushed branch stays on the remote, and
`/task start <task> <repo>` picks it up again for review fixes.

### Code graphs

[code-review-graph](https://github.com/tirth8205/code-review-graph) parses a repo
into a graph of calls, imports and tests, so a review can ask what a change
touches without reading the whole codebase. Install it once per machine:

```
pipx install code-review-graph
```

Then use it through `/graph`, never directly. Run bare, the tool writes its
data into the repo it reads. `graph.sh` keeps every graph under a gitignored
`.code-review-graph/` at the root instead:

```
/graph                                   what is built, and whether it is fresh
/graph build api                         graph that repo's own checkout
/graph review hotfix-payment             what each repo's change touches, against its base
/graph run hotfix-payment/api query callers_of applyPromo
```

`/plan-prd` runs `review` before dispatching the reviewers, so it needs no
typing during a task. `/task finish` drops a task's graphs along with it.
Builds leave out generated code, migrations and vendored packages, listed in
the tracked `.code-review-graphignore`.

Every build also rewrites `.mcp.json`, which is gitignored: one read-only MCP
server per checkout that has a graph, so the graph can be queried as a tool.
Each serves `repos/<repo>` from the graph `graph.sh` built and exposes only the
six tools that read. Nothing is registered until something is built:

```
/graph build all
```

Do **not** run `code-review-graph install`. It writes 15 files into the repo it
targets — MCP configs, instruction files, an append to that repo's `CLAUDE.md`
— and a hook that rebuilds the graph inside the checkout. Those files would land
in a task's pull request.

## `task.sh` reference

The slash command is a thin wrapper; the script runs standalone too.

```
.claude/scripts/task.sh start <task> [repos] [flags]     start a task, or add repos to one
.claude/scripts/task.sh where <task> [repo]              the working directory, or one per repo
.claude/scripts/task.sh root                             the workspace root, absolute
.claude/scripts/task.sh list [task]                      open tasks, dirty state per repo
.claude/scripts/task.sh repos                            the roster, read from disk
.claude/scripts/task.sh config                           resolved settings and their source
.claude/scripts/task.sh report <task>                    read-only facts for a wrap-up
.claude/scripts/task.sh finish <task> [repos] [flags]    release the working directories
```

Start flags:

| Flag                 | Effect                                                        |
| -------------------- | ------------------------------------------------------------- |
| `--from <ref>`       | Base ref for new branches. Default `TASK_DEFAULT_BASE`.        |
| `--from a=x,b=y`     | Per-repo base refs, e.g. `api=origin/release-2`.               |
| `--space`            | Work in worktrees under `spaces/<task>/`.                      |
| `--inplace`          | Work in `repos/<repo>` itself (the default).                   |
| `--branch <name>`    | Override the branch name (default `<prefix>/<task>`).          |
| `--no-fetch`         | Skip `git fetch`; use whatever refs are already local.         |
| `--no-env`           | Don't copy `.env*` files into new worktrees.                   |
| `--dry-run`          | Print what would happen, write nothing.                        |

Finish flags: `--delete-branch` (also drop the local branch), `--force`
(discard uncommitted work / unpushed commits).

`report` is what makes the log possible — it prints the isolation, each repo's
working directory, branch, recorded base, commit subjects, a diffstat, and
changed file paths, without touching anything.

## How it behaves

- **Branch naming** — `<prefix>/<task>` by default, the same branch in every repo
  of the task, so a task is one name everywhere. `<prefix>` is per machine, so
  two people working the same task get branches that differ only by prefix.
- **Branch reuse** — if `<prefix>/<task>` already exists locally or on `origin`, the
  repo joins it instead of failing. Adding a repo to an open task, or re-running
  the same command, is safe.
- **One isolation per task** — every repo in a task works the same way; adding a
  repo to an open task keeps its isolation.
- **Env files** — for a space, `.env`, `.env.local`, `.env.development` and
  `.env.*.local` are copied from `repos/<repo>` into each new worktree, since
  worktrees only carry tracked files. In place, the checkout already has them.
- **Base tracking** — the base ref and commit are recorded in
  `.claude/state/tasks/<task>`, so `report` can still state the true starting
  point long after the branch has moved on. An in-place task also records the
  branch each checkout was on, which is where `finish` puts it back.
- **Partial failures** — if a base ref doesn't exist for one repo, or a repo is
  busy, that repo is skipped and reported; the rest of the task still starts.
- **All-or-nothing finish** — `finish` checks every repo before touching any,
  so a blocked finish leaves the task intact rather than half released.
- **Reads come from refs** — scripts that describe a repo (release notes, learned
  facts, graphs) read its default branch or the task's base, never a working tree
  a task may have moved.

## Settings

Branch prefix, default base ref and default isolation are **per machine**, not
per workspace. They live in a gitignored `.env` at the root, so everyone differs
without touching a tracked file:

```
cp .env.example .env
```

```
TASK_BRANCH_PREFIX=<your-handle>   # branches become <your-handle>/<task>
TASK_DEFAULT_BASE=origin/main      # base ref when --from is not given
TASK_DEFAULT_ISOLATION=inplace     # or space
```

Highest wins: the environment, then `.env`, then a built-in default. So a
one-off override works without editing anything:

```
TASK_BRANCH_PREFIX=spike .claude/scripts/task.sh start try-it api
```

The `TASK_*` settings were called `SPACE_*` before; the old names are still read,
and `/task config` says when one is. `.env.example` is the tracked template and
lists every setting.

Because the prefix differs per person, **no doc in this repo names one** —
they all write `<prefix>/<task>`. Do not paste a real prefix into a PRD, a
plan, or a README; it would be wrong for everyone else.

### Editor search

`repos/`, `spaces/` and `docs/` are all gitignored — their contents belong to
the service repos, or describe private incidents. VS Code honours `.gitignore`,
so out of the box cmd+P and the search panel could not see any of them.

The tracked `.ignore` at the root fixes that. Search tools read it and give it
precedence over `.gitignore` in the same directory; git never reads it, so what
is tracked does not change. Every `.gitignore` *inside* a repo or worktree still
applies, so `node_modules/` and `dist/` stay out of the results.
`.vscode/settings.json` pins the settings that keep it working. Both files are
tracked, so a fresh clone gets working search with no setup.

## Keeping the system honest

The workspace changes; the prose describing it does not. `/ccs` checks the two
against each other — undocumented checkouts, dangling skill references, commands
missing frontmatter, branch prefixes that have drifted, skills carrying one
repo's facts — and proposes one fix at a time. `/ccs note <what got in the way>`
records friction mid-task, while it is still true, into `.claude/ccs-notes.md`.

Changes to the system land in this repo directly. It is not a service, so it has
no task and no `/pr`; `ccs-conventions` describes how its pieces are shaped.

## Rules

- A source branch is never deleted, and reference repos are read-only — see
  `CLAUDE.md`. A `PreToolUse` hook (`.claude/scripts/guard.sh`) enforces both, so
  this is not a matter of judgment.
- Read a repo's `AGENTS.md` before planning or writing in it, and follow it over
  any skill here. It belongs to that repo's team: change it in a task, through
  `/pr`, and never restate it under `.claude/`.
- A repo listed in `REFERENCE_REPOS` is read-only everywhere, in `repos/` and in
  any space. The same hook enforces that.
- `git add`, `git commit`, and `git push` of the task branch are fine in a task's
  working directories. Committing happens once, at the end, through `/pr` — not
  as checkpoints during a build — and work reaches the base branch only through
  the PR.
- Finish a task with `/task finish`, not `rm -rf` or a hand-made `git switch`. A
  raw delete leaves git's worktree registry pointing at a directory that's gone,
  a hand switch leaves the task's metadata behind, and both skip the log.
