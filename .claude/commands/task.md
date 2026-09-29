---
description: Start, list, locate or finish a task across one or more repos - in place by default, or in a worktree space with --space
argument-hint: start <task> [repos] [--from <ref>] [--space] | finish <task> [--force] | list | where <task> [repo] | repos | config
allowed-tools: Bash(.claude/scripts/task.sh:*), Read, Write
---

## Result

!`.claude/scripts/task.sh slash $ARGUMENTS`

## What this is

A **task** is one feature, bugfix or hotfix, on one branch - `<prefix>/<task>` -
in every repo it touches. Where that branch is worked on is the task's
**isolation**, chosen when it starts and the same for every repo in it:

| | In place (default) | Space (`--space`) |
|---|---|---|
| Working directory | `repos/<repo>`, switched to the task branch | `spaces/<task>/<repo>`, a git worktree |
| Use when | the usual case | parallel tasks on the same repo, long-lived work, or the repo is busy |
| Finish | the checkout returns to its base branch | the worktree is removed |

Both kinds can be open at once. Git forbids only the same branch in two working
trees, and every task has its own. The one impossible case is two in-place tasks
on the same repo: `start` refuses a repo that is dirty or on another task's
branch and says to use `--space`. It never changes a task's layout on its own.

**Never build a task's path yourself.** Ask for it:

```
.claude/scripts/task.sh where <task> <repo>    one repo's working directory
.claude/scripts/task.sh where <task>           repo<TAB>dir for every repo
```

"Task", "space", "feature", "story", "bugfix" and "hotfix" all mean the same
thing here; `.claude/` calls it a **task**. One kebab-case name is reused
everywhere: the branch, `docs/<YYYY-MM-DD>_<task>/`, and, for a space,
`spaces/<task>/`. Pick it once and never rename it mid-flight. Find a task's docs
with `ls -d docs/*_<task>/`, never by guessing the date.

**Repo aliases are read from disk, never from a list in this file.** Any git
checkout directly under `repos/` is a repo, and its directory name is its alias;
a longer service name resolves by prefix. `/task repos` prints the roster.
Cloning a new service into `repos/` makes it available immediately - do not add
it to any doc.

**Omitting the repo list means every workable checkout in `repos/`**, however
many that is today. That is rarely what a task wants. If the user did not say
which repos the work touches, ask, or read it from the PRD - do not let the
default decide, and say in your report exactly which repos joined.

**Reference-only repos never join a task.** `REFERENCE_REPOS` in `.env` lists
aliases that exist to be read, never worked on; they are skipped in the default
set, and naming one explicitly fails. That is correct, not a bug to route
around - do not retry under a different name or suggest editing `.env`. Say which
repo is reference-only and let the user decide.

```
/task start fix-promo api,web --from origin/feature/m5.1
/task start rework-booking api --from origin/develop --space
/task start hotfix-payment api --from api=origin/release-2
/task list
/task where fix-promo api
/task repos
/task config
/task finish fix-promo
```

The branch is `<prefix>/<task>`, where `<prefix>` is `TASK_BRANCH_PREFIX`
resolved per machine - environment, then a gitignored `.env`, then a built-in
default. **Never state a literal prefix**, in a report or in a file you write;
read the real branch off the result above, which always prints what it used.

`--from` is the **source branch** - the base ref new branches start from. Pass
one ref for everything, or `repo=ref` pairs to differ per repo. The script has a
default, but an agent must never choose it silently: if the user did not say
where the task branches from, ask before starting it. The result always prints
the base and commit it actually used, so check it matches what you intended.

## Your job

The first line of the result says which `mode` ran. Follow the matching
section below and ignore the others.

Per this project's CLAUDE.md: checkouts in `repos/` are writable like a space's
worktrees, and a source branch is never deleted - the guard hook enforces that.
Committing is `/pr`'s job at the end of a task, not something to do while it is
being worked. A repo in `REFERENCE_REPOS` is read-only everywhere.

### mode: start - the task has already started

Report the result concisely: its isolation, which repos joined, which were
skipped or failed, the branch, and the base commit each one started from. If any
repo failed, say why and stop - do not retry with different flags, switch
isolation, or invent a different base ref; those choices are the user's. A busy
repo is the usual reason, and the error names it.

Then give the working directories the result printed. Do not start editing code
unless the user asked for that in the same message.

The session is now bound to this task. Point at what comes next, using the same
task name throughout:

```
/plan-prd <idea>                    -> docs/<date>_<task>/prd.md  (also starts the task)
/plan docs/<date>_<task>/prd.md     -> docs/<date>_<task>/plan.md
tdd-workflow <plan path>            -> implementation in each repo's working directory
```

### mode: list - nothing else to do

Relay the listing: each open task, its isolation, and which repos are dirty. An
in-place task holding a repo is worth saying out loud - that repo cannot take a
second in-place task until it finishes.

### mode: where - nothing else to do

Relay the path. It is the only correct answer to "where do I work on this".

### mode: config - nothing else to do

Relay what each setting resolved to and which layer won: the environment, the
gitignored `.env`, or the built-in default. A value read under an old `SPACE_*`
name still works; say it can be renamed.

This is the answer to "what will my branch be called" and "will a new task work
in place". Never answer those from memory or from a doc - they differ per
machine. If the user wants to change one, they edit `.env` (`cp .env.example
.env` if they have none); a one-off is an environment variable on the command.

### mode: repos - nothing else to do

Relay the roster: which repos are checked out, their remotes, and which open
tasks use them. This is the answer to "what can I work on" and to "what would a
bare `/task start` include". Any checkout marked `reference-only` is neither.

If a repo the user expects is missing, the fix is to clone it into `repos/` -
theirs to do, since the guard blocks writes there. Never propose editing a doc to
add it; nothing in the workspace keeps a list.

### mode: finish - nothing has changed yet

The result is a **read-only report**, taken while the working directories still
hold the task. Once a worktree is removed or a checkout switched back, those
diffs are out of reach, so **write the summary first, finish second.** Never
reverse that order.

#### 1. Check it is safe to finish

Read the report. For every repo, stop and report back to the user WITHOUT
finishing anything if either is true:

- `uncommitted` is greater than 0 - there is work in progress there.
- `unpushed` is greater than 0 - commits exist on no remote, so deleting the
  branch would destroy them.

Say which repo and which condition, and let the user decide. They can push or
stash and re-run, or pass `--force` to discard deliberately. The report's
`force` line says whether they already did; do not pass `--force` yourself
unless it is `1`.

#### 2. Write the log

The log belongs in the task's own directory, as
`docs/<YYYY-MM-DD>_<task>/log.md`. The report's `docs` line names that directory
- a task that came through `/plan-prd` already has one, holding its PRD and its
plans, and the log joins them there.

If the `docs` line reads `-`, this task ran outside the documented flow and has
no directory yet. Create `docs/<today>_<task>/` using the report's `today` line
- never a date from memory - and say in your report that the task had no PRD.

The date in that directory name is the day the task **opened**, so an existing
directory keeps its name no matter how long the task ran. Never rename one to
the closing date; the closing date goes inside the file.

If `log.md` is already there, read it and revise it in place rather than
appending a second wrap-up. Use this shape:

```markdown
# <task>

- **Branch:** <prefix>/<task>
- **Repos:** <repo>, <repo> · **Isolation:** inplace | space
- **Base:** <source branch>
- **Opened:** <YYYY-MM-DD> · **Closed:** <YYYY-MM-DD>

## What this was for

One or two sentences of intent, in plain language.

## What changed

- **<repo>** - what actually changed here and why it mattered.
- **<repo>** - same, per repo.

## Worth remembering

Decisions, gotchas, or surprises a future reader would want. Omit if there
were none - do not pad this.
```

Write the summary at the altitude of "what happened and why", not a commit
list. The report gives you commit subjects, a diffstat, and changed file
paths per repo - read the file paths and subjects and say what the work
actually did. If the evidence is too thin to tell, say so plainly instead of
inventing a narrative. Never guess at intent the commits do not support.

#### 3. Finish

Only after the log file is written:

```
.claude/scripts/task.sh finish <task> --delete-branch
```

Add `--force` only if the report's `force` line is `1`. Then confirm to the
user: the log path, which working directories were released (worktrees removed,
or checkouts back on their base branch), and which branches were deleted. If work
needs committing before finishing, that is the user's to do.

### mode: error

Relay the message. It names what exists. Do not guess another subcommand.
