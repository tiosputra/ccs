---
description: Create or tear down a multi-repo worktree space for a feature/bugfix/hotfix
argument-hint: add <task> [repos] [--from <ref>] | remove <task> [--force] | list | repos | config
allowed-tools: Bash(.claude/scripts/space.sh:*), Read, Write
---

## Result

!`.claude/scripts/space.sh slash $ARGUMENTS`

## What this is

A **space** is one task checked out across several services at once, as git
worktrees grouped under `spaces/<task>/`:

```
spaces/fix-promo/backend    -> repos/backend    on <prefix>/fix-promo
spaces/fix-promo/sport      -> repos/sport      on <prefix>/fix-promo
```

"Task", "space", "product", "feature", "story", "bugfix", and "hotfix" all mean
the same thing here; `.claude/` calls it a **task**. One kebab-case task name is
reused everywhere, so a task is one word across the whole workspace:

| Artifact | Path / name |
|---|---|
| Space (worktrees) | `spaces/<task>/<repo>/` |
| Branch | `<prefix>/<task>` — `<prefix>` is per machine, see `/space config` |
| Task docs | `docs/<YYYY-MM-DD>_<task>/` — one directory for everything written |
| PRD | `docs/<YYYY-MM-DD>_<task>/prd.md` |
| Plan | `docs/<YYYY-MM-DD>_<task>/plan.md`, then `plan-m2.md` per later milestone |
| API contract | `docs/<YYYY-MM-DD>_<task>/api-contract.md` — what consumers see change |
| TDD evidence | `docs/<YYYY-MM-DD>_<task>/testing.md` — one section per repo |
| Wrap-up log | `docs/<YYYY-MM-DD>_<task>/log.md` |

Pick the name once and never rename it mid-flight. The date in the docs
directory is the day the task opened and never changes; find an existing one
with `ls -d docs/*_<task>/`, never by guessing the date.

**Repo aliases are read from disk, never from a list in this file.** Any git
checkout directly under `repos/` is a repo and its directory name is its alias;
a longer service name resolves by prefix, so `sport-service` finds `sport`.
`/space repos` prints the current roster. Cloning a new service into `repos/`
makes it available immediately — do not add it to any doc.

**Omitting the repo list means every workable checkout in `repos/`**, however
many that is today. That is rarely what a task wants. If the user did not say
which services the work touches, ask, or infer it from the PRD — do not let the
default decide, and say in your report exactly which repos were created.

**Reference-only repos get no worktree.** `REFERENCE_REPOS` in `.env` lists
aliases that exist to be read, never worked on; they are skipped in the default
set, and naming one explicitly fails with an error rather than a warning. That
is correct, not a bug to route around — do not retry under a different name or
suggest editing `.env`. Say which repo is reference-only and let the user
decide.

```
/space add fix-promo backend,player --from origin/feature/m5.1
/space add feature-booking --from origin/develop
/space add hotfix-payment backend --from backend=origin/release-2
/space list
/space repos
/space config
/space remove fix-promo
```

The branch a space gets is `<prefix>/<task>`, where `<prefix>` is
`SPACE_BRANCH_PREFIX` resolved per machine — environment, then a gitignored
`.env`, then a built-in default. **Never state a literal prefix**, in a report
or in a file you write; read the real branch off the result above, which always
prints what it created.

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
The exception is a repo listed in `REFERENCE_REPOS`: that one is read-only in a
space too, and the guard blocks writes there as well.

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
/plan-prd <idea>                    -> docs/<date>_<task>/prd.md  (also opens the space)
/plan docs/<date>_<task>/prd.md     -> docs/<date>_<task>/plan.md
tdd-workflow <plan path>            -> implementation inside spaces/<task>/<repo>/
```

### mode: list — nothing else to do

Relay the listing. Say which spaces are dirty.

### mode: config — nothing else to do

Relay what each setting resolved to and which layer won: the environment, the
gitignored `.env`, or the built-in default.

This is the answer to "what will my branch be called". Never answer that from
memory or from a doc — no tracked file names a prefix, because it differs per
machine. If the user wants to change it, they edit `.env` (`cp .env.example
.env` if they have none); a one-off is an environment variable on the command.

### mode: repos — nothing else to do

Relay the roster: which services are checked out, their remotes, and which
open spaces are using them. This is the answer to "what can I work on" and to
"what would a bare `/space add` create". Any checkout marked `reference-only`
is neither: it is there to be read and asked about, and no space will ever open
a worktree for it.

If a service the user expects is missing, the fix is to clone it into `repos/`
— which is theirs to do, since the guard blocks writes there. Never propose
editing a doc to add it; nothing in the workspace keeps a list.

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

The log belongs in the task's own directory, as
`docs/<YYYY-MM-DD>_<task>/log.md`. The report's `docs` line names that directory
— a task that came through `/plan-prd` already has one, holding its PRD and its
plans, and the log joins them there.

If the `docs` line reads `-`, this task ran outside the documented flow and has
no directory yet. Create `docs/<today>_<task>/` using the report's `today` line
— never a date from memory — and say in your report that the task had no PRD.

The date in that directory name is the day the task **opened**, so an existing
directory keeps its name no matter how long the task ran. Never rename one to
the closing date; the closing date goes inside the file.

If `log.md` is already there, read it and revise it in place rather than
appending a second wrap-up. Use this shape:

```markdown
# <task>

- **Branch:** <prefix>/<task>
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
