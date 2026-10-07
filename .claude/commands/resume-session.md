---
description: Load an open task's log.md and brief the session on where the work stands, before doing anything
argument-hint: "[task]"
allowed-tools: Bash(.claude/scripts/task.sh logs:*), Bash(.claude/scripts/task.sh report:*), Bash(ls:*), Read, Glob
---

## Result

!`.claude/scripts/task.sh logs`

## What this is

The counterpart to `/save-session`. A task's working memory is its
`docs/<YYYY-MM-DD>_<task>/log.md`: a `## Current state` section that the last save
overwrote, and a `## Sessions` history that every save appended to. This command
reads it and briefs the session — it does not start work.

The result above has one row per open task:
`log<TAB><task><TAB><path or -><TAB><last saved or -><TAB><open|closed|none>`. A new
session may already have seen the open ones: the `SessionStart` hook prints them.

## Your job

### 1. Find the log

- **`$ARGUMENTS` names a task** — take its row. A task with no row is not open: say
  so, and stop.
- **No argument** — take the `open` row with the newest last-saved date. If two were
  saved the same day, list them and ask which.
- **State `none`** — the task has no saved session yet (`/save-session` writes one).
  Offer to brief from its `prd.md` and `plan.md` instead (`ls -d docs/*_<task>/`), and
  stop there.
- **State `closed`** — `/task finish` already wrote the wrap-up: say so, and offer it
  as reading rather than resuming it.

### 2. Read, then check it against the workspace

Read the whole log, then each file under **Load first**. Run
`.claude/scripts/task.sh report <task>`, and note anything the log no longer
matches: a file it names that is gone, commits since the last session, uncommitted
work it does not mention. The log was true when it was written; the report is true
now.

### 3. Brief

```
RESUMED: <task> — docs/<date>_<task>/log.md
Last saved: <date of the newest session entry> (<N> days ago)

BUILDING:
<the Building line, in your own words>

STATE:
  In progress: <items>
  Changed since the save: <from the report, or "nothing">

DO NOT RETRY:
<every "Did not work" item across ALL session entries, with its reason —
 or "Nothing has failed so far.">

DECIDED:
<every "Decided" item across all entries — so they are not relitigated>

BLOCKERS:
<items, or "None.">

NEXT STEP:
<the Next step line>
```

**Do not retry** is never skipped: it is the reason the log exists. Flag a save more
than 7 days old.

### 4. Wait

Do not touch a file until the user says what to do. If they say "continue" and the
next step is defined, do exactly that step, inside the task's working directory
(`task.sh where <task> <repo>`).

Reading the log never changes it.
