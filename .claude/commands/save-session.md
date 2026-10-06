---
description: Save where the active task stands into its log.md, so a later session can pick it up with /resume-session
argument-hint: "[task]"
allowed-tools: Bash(.claude/scripts/task.sh list:*), Bash(.claude/scripts/task.sh report:*), Bash(git -C * diff:*), Bash(git -C * status:*), Read, Write, Edit, Glob
---

## Result

!`.claude/scripts/task.sh list`

## What this is

A task's working memory lives in one file: `docs/<YYYY-MM-DD>_<task>/log.md`, the
same file `/task finish` later turns into the task's wrap-up. `/save-session` writes
what this session learned into it; `/resume-session` reads it back in a fresh
session. There is no second store — nothing goes to `~/.claude/`, and nothing goes
inside a service repo.

The result above lists the open tasks.

## Your job

### 1. Pick the task

The task is `$ARGUMENTS` if given, else the session's active task — the one its PRD,
plan, or `/task start` named. If the session has none, or it is not in the list
above, say so and stop. Work on the workspace system itself is not a task and has no
log; offer `/ccs note` for anything worth keeping from it.

### 2. Gather the facts

Run `.claude/scripts/task.sh report <task>`. Its `docs` line is the task's directory
and its `today` line is the date — never a date from memory. Its per-repo lines give
each working directory, uncommitted count and changed files; read those rather than
re-deriving them. For an uncommitted repo, `git -C <workdir> diff --stat` shows what
moved.

If `docs` reads `-`, the task ran outside `/plan-prd` and has no directory: create
`docs/<today>_<task>/` and say so.

Then add what only this conversation knows: what was attempted, what failed and
the exact reason, what was decided, what is still open.

### 3. Write log.md

If `log.md` does not exist, create it with the header and both sections below. If it
does, read it first, then **replace** `## Current state` and **append** one entry to
`## Sessions`. Never edit an earlier session entry — those are history.

If the header's `Closed` holds a date, the task is finished: stop and say so rather
than reopening it.

```markdown
# <task>

- **Branch:** <branch line from the report>
- **Repos:** <repo>, <repo> · **Isolation:** inplace | space
- **Base:** <base ref>
- **Opened:** <date from the docs directory name> · **Closed:** —

## Current state

**Building:** one or two sentences — enough for someone with no memory of this task.

**Next step:** the single most important thing to do on resume, precise enough to
start without thinking. If it is not known, say what has to be decided first.

**In progress:**
- `<repo>`: `<path>` — what is done, what is left

**Blockers / open questions:**
- …or "None."

**Load first:** the files a resuming session should read before anything else —
usually `prd.md`, the current `plan*.md`, and the one or two code files in flight.

## Sessions

### <today> — <one-line topic>

**Worked** (with evidence — a passing test, a 200, a log line):
- <thing> — confirmed by <evidence>

**Did not work** (exact reason, so it is never retried):
- <approach> — failed because <error or cause>

**Decided:**
- <decision> — because <reason>
```

Leave out a session sub-heading that has nothing in it, except **Did not work**,
which says "Nothing failed." when empty — a resuming session needs to know nothing
was tried and lost, as much as what was.

`Closed` stays `—` until `/task finish`; that dash is what marks the task as still
open to `/ccs`.

### 4. Show it

Print the new `## Current state` and the session entry, name the file, and ask
whether anything is wrong or missing. Edit on request.

## What not to do

- Do not write the wrap-up sections (`What this was for`, `What changed`, `Worth
  remembering`) — those are `/task finish`'s, written when the task closes.
- Do not set `Closed`, commit the file, or touch a closed task's log.
- Do not record a "worked" item without evidence; put it under **In progress**.
