# swing

A control workspace for working on the Getswing services in parallel.

Instead of one checkout per service and a lot of branch-switching, this
workspace keeps **one canonical checkout per service** and hands each task its
own set of git worktrees. A task gets its own directory, its own branch across
every service it touches, and its own wrap-up note when it's done.

That means several tasks can be open at once — a hotfix, a feature, an
experiment — each fully isolated, with no stashing and no `git checkout`
whiplash between them.

## Layout

```
swing/
├── repos/                  canonical checkouts — the source of truth
│   ├── backend/                Getswing-Team/backend
│   ├── sport/                  Getswing-Team/sport-service
│   └── player/                 Getswing-Team/player-service
│
├── spaces/                 one directory per task, worktrees inside
│   └── add-label/
│       ├── backend/            -> repos/backend    on ccs/add-label
│       └── sport/              -> repos/sport      on ccs/add-label
│
├── prds/                   one PRD per task, <YYYY-MM-DD>_<task>.md
├── plans/                  one plan per milestone, <task>-m<N>.plan.md
├── space-log/              wrap-up notes, one per finished task
├── release/                deployment runbooks, one per release
│
├── .claude/
│   ├── commands/           /plan-prd, /plan, /space, /pr
│   ├── skills/             tdd-workflow and the pattern skills
│   ├── agents/             the reviewers
│   └── scripts/
│       ├── space.sh        creates and tears down spaces
│       └── guard.sh        PreToolUse hook - keeps repos/ read-only
```

Nothing in `repos/` is ever worked in directly — treat those checkouts as
read-only origins. All editing happens in `spaces/<task>/<repo>/`.

## Repos

| Alias    | Directory       | GitHub                            |
| -------- | --------------- | --------------------------------- |
| `backend`| `repos/backend` | `Getswing-Team/backend`           |
| `sport`  | `repos/sport`   | `Getswing-Team/sport-service`     |
| `player` | `repos/player`  | `Getswing-Team/player-service`    |

The full service name works too — `sport-service` resolves to `sport`.

## The task flow

One command runs a task end to end, stopping twice to ask you:

```
/plan-prd add promo codes from branch origin/feature/m5.1
      |
      |   writes prds/add-promo-codes.prd.md
      |   the PRD proposes the space: repos, source branch, new branch, PR base
      |   nothing is created yet
      |
 [GATE 1]  you read the PRD and confirm - or correct the repos / source branch
      |
      |   space.sh add            -> spaces/add-promo-codes/<repo>/
      |   /plan                   -> plans/add-promo-codes-m1.plan.md
      |   tdd-workflow            -> implementation, RED/GREEN, evidence report
      |   go- / typescript-reviewer -> CRITICAL and HIGH findings fixed
      |
 [GATE 2]  it reports what changed and stops, uncommitted
      |
    /pr     stage, commit, push ccs/add-promo-codes, open one PR per repo
```

Those two stops are the whole point: you read the requirements before a branch
exists, and you see the finished work before anything is pushed.

`/plan`, `/space`, and `/pr` all still work standalone if you want a single step.

## Everyday use

Everything space-related goes through one command: `/space add | remove | list`.

Start a task across every service:

```
/space add feature-booking
```

Start one across just two, based off a release branch:

```
/space add hotfix-payment backend,sport --from origin/release-2
```

See what's open, and whether anything is dirty:

```
/space list
```

Finish up. This writes `space-log/<task>.md` **before** removing anything, so
the summary is captured while the diffs still exist:

```
/space remove feature-booking
```

`remove` refuses to tear down a space that has uncommitted changes or commits
that have not reached any remote. Push or stash first, or pass `--force` to
discard on purpose.

(`/spaceclear <task>` is the older standalone teardown command and still works;
`/space remove` supersedes it.)

## `space.sh` reference

The slash command is a thin wrapper; the script runs standalone too.

```
.claude/scripts/space.sh add <task> [repos] [flags]     create a space
.claude/scripts/space.sh list [task]                    list spaces, show dirty state
.claude/scripts/space.sh report <task>                  read-only facts for a wrap-up
.claude/scripts/space.sh remove <task> [repos] [flags]  tear down
```

Add flags:

| Flag              | Effect                                                        |
| ----------------- | ------------------------------------------------------------- |
| `--from <ref>`    | Base ref for new branches. Default `origin/main`.              |
| `--from a=x,b=y`  | Per-repo base refs, e.g. `backend=origin/release-2`.           |
| `--branch <name>` | Override the branch name (default `ccs/<task>`).               |
| `--no-fetch`      | Skip `git fetch`; use whatever refs are already local.         |
| `--no-env`        | Don't copy `.env*` files into the new worktrees.               |
| `--dry-run`       | Print what would happen, write nothing.                        |

Remove flags: `--delete-branch` (also drop the local branch), `--force`
(discard uncommitted work / unpushed commits).

`report` is what makes the log possible — it prints the branch, the recorded
base, commit subjects, a diffstat, and changed file paths per repo, without
touching anything.

## How it behaves

- **Branch naming** — `ccs/<task>` by default, the same branch in every repo of
  the space, so a task is one name everywhere.
- **Branch reuse** — if `ccs/<task>` already exists locally or on `origin`, the
  worktree joins it instead of failing. Adding a repo to an existing space, or
  re-running the same command, is safe.
- **Env files** — `.env`, `.env.local`, `.env.development`, `.env.*.local` are
  copied from `repos/<repo>` into each new worktree. Worktrees only carry
  tracked files, so without this the services won't boot.
- **Base tracking** — the base ref and commit are recorded in
  `spaces/<task>/.space`, so `report` can still state the true starting point
  long after the branch has moved on.
- **Partial failures** — if a base ref doesn't exist for one repo, that repo is
  skipped and reported; the rest of the space is still created.
- **All-or-nothing teardown** — `remove` checks every repo before removing any,
  so a blocked teardown leaves the space intact rather than half dismantled.

Two env vars change the defaults:

```
SPACE_BRANCH_PREFIX=ccs          # branch prefix
SPACE_DEFAULT_BASE=origin/main   # default base ref
```

## Rules

- Never write anything under `repos/` — see `CLAUDE.md`. A `PreToolUse` hook
  (`.claude/scripts/guard.sh`) enforces it, so this is not a matter of judgment.
- `git add`, `git commit`, and `git push` are fine **inside a space**. Committing
  happens once, at the end, through `/pr` — not as checkpoints during a build.
- Tear a space down with `/space remove`, not `rm -rf`. A raw delete leaves
  git's worktree registry pointing at a directory that's gone, and skips the
  log entirely.
