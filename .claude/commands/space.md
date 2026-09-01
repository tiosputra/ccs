---
description: Create or tear down a multi-repo worktree space for a feature/bugfix/hotfix
argument-hint: add <task> [repos] [--from <ref>] | remove <task> [--force] | list
allowed-tools: Bash(.claude/scripts/space.sh:*), Read, Write
---

## Result

!`.claude/scripts/space.sh slash $ARGUMENTS`

## What this is

A **space** is one task checked out across several services at once, as git
worktrees grouped under `spaces/<task>/`:

```
spaces/fix-promo/backend    -> repos/backend    on ccs/fix-promo
spaces/fix-promo/sport      -> repos/sport      on ccs/fix-promo
spaces/fix-promo/player     -> repos/player     on ccs/fix-promo
```

"Task", "space", "product", "feature", "story", "bugfix", and "hotfix" all mean
the same thing here; `.claude/` calls it a **task**. One kebab-case task name is
reused everywhere, so a task is one word across the whole workspace:

| Artifact | Path / name |
|---|---|
| Space (worktrees) | `spaces/<task>/<repo>/` |
| Branch | `ccs/<task>` |
| PRD | `prds/<YYYY-MM-DD>_<task>.md` |
| Plan | `plans/<task>-m<N>.plan.md` |
| TDD evidence | `spaces/<task>/<repo>/docs/testing/<task>.tdd.md` |
| Wrap-up log | `space-log/<YYYY-MM-DD>-<task>.md` |

Pick the name once and never rename it mid-flight.

Repo aliases: `backend`, `sport` (sport-service), `player` (player-service).
Omit the repo list to use all three.

```
/space add fix-promo backend,player --from origin/feature/m5.1
/space add feature-booking --from origin/develop
/space add hotfix-payment backend --from backend=origin/release-2
/space list
/space remove fix-promo
```

`--from` is the **source branch** — the base ref new branches start from. Pass
one ref for everything, or `repo=ref` pairs to differ per service. The script
defaults to `origin/main`, but an agent must never choose it silently: if the
user did not say where the task branches from, ask before creating the space.
The run always prints the base and commit it actually used, so check the result
above matches what you intended.

## Your job

The first line of the result says which `mode` ran. Follow the matching
section below and ignore the others.

Per this project's CLAUDE.md: never write anything under `repos/` - those
checkouts are read-only origins, and the guard hook blocks it. All editing, and
all committing, happens in `spaces/<task>/<repo>/`. Committing itself is `/pr`'s
job at the end of a task, not something to do while a space is being worked.

### mode: add — worktrees are already created

Report the result concisely: which repos got a worktree, which were skipped
or failed, the branch name, and the base commit each one started from. If any
repo failed, say why and stop — do not retry with different flags or invent a
different base ref; that choice is the user's.

Then tell them the space path so they can `cd` into it. Do not start editing
code unless they asked for that in the same message.

The session is now bound to this task. Point at what comes next, using the same
task name throughout:

```
/plan-prd <idea>                  -> prds/<date>_<task>.md  (also opens the space)
/plan prds/<date>_<task>.md -> plans/<task>-m<N>.plan.md
tdd-workflow <plan path>          -> implementation inside spaces/<task>/<repo>/
```

### mode: list — nothing else to do

Relay the listing. Say which spaces are dirty.

### mode: remove — nothing has been removed yet

The result is a **read-only report**, taken while the worktrees still exist.
Once they are removed those diffs are gone, so **write the summary first,
tear down second.** Never reverse that order.

#### 1. Check it is safe to remove

Read the report. For every repo, stop and report back to the user WITHOUT
removing anything if either is true:

- `uncommitted` is greater than 0 — there is work in progress there.
- `unpushed` is greater than 0 — commits exist on no remote, so deleting the
  branch would destroy them.

Say which repo and which condition, and let the user decide. They can push or
stash and re-run, or pass `--force` to discard deliberately. The report's
`force` line says whether they already did; do not pass `--force` yourself
unless it is `1`.

#### 2. Write the log

Name the file `space-log/<YYYY-MM-DD>-<task>.md`, e.g.
`space-log/2026-08-28-fix-promo.md`. Take the date from the report's `today`
line — that is the day the space closed, and it keeps the directory sorted
chronologically. Do not use a date from memory.

Check for an earlier log of the same task first (`ls space-log/*-<task>.md`).
If one exists, read it and revise it under its existing name rather than
creating a second file. Use this shape:

```markdown
# <task>

- **Branch:** ccs/<task>
- **Repos:** backend, sport
- **Base:** origin/feature/m5.1
- **Opened:** 2026-08-28 · **Closed:** 2026-09-02

## What this was for

One or two sentences of intent, in plain language.

## What changed

- **backend** — what actually changed here and why it mattered.
- **sport** — same, per repo.

## Worth remembering

Decisions, gotchas, or surprises a future reader would want. Omit if there
were none — do not pad this.
```

Write the summary at the altitude of "what happened and why", not a commit
list. The report gives you commit subjects, a diffstat, and changed file
paths per repo — read the file paths and subjects and say what the work
actually did. If the evidence is too thin to tell, say so plainly instead of
inventing a narrative. Never guess at intent the commits do not support.

#### 3. Tear down

Only after the log file is written:

```
.claude/scripts/space.sh remove <task> --delete-branch
```

Add `--force` only if the report's `force` line is `1`. Then confirm to the
user: the log path, which worktrees were removed, and which branches were
deleted. If work needs committing before teardown, that is the user's to do.
