---
description: Check the health of the workspace system itself, or record one line of friction to fix later
argument-hint: "[check] | note <what got in the way> | notes"
allowed-tools: Bash(.claude/scripts/ccs.sh:*), Read, Write, Edit, Glob, Grep
---

## Result

!`.claude/scripts/ccs.sh slash $ARGUMENTS`

## What this is

`/space` looks after a task. `/ccs` looks after the thing that runs tasks: the
commands, skills, scripts and rules under `.claude/`, and whether they still
describe this workspace as it actually is.

The system decays in one direction — the workspace changes, and the prose that
describes it does not. A repo gets cloned and no doc mentions it. A skill gets
referenced before it is written. A doc pastes in one person's branch prefix,
which is wrong for everyone else. None of that breaks anything loudly; it just
makes the next session slightly wronger than the last.

```
/ccs                              what is out of date right now
/ccs note the guard blocks 2>/dev/null after cd repos/
/ccs notes                        everything recorded so far
```

The first line of the result says which `mode` ran.

## mode: check

Findings are `finding<TAB>severity<TAB>area<TAB>message`; clean areas print
`ok`. The script measures and ranks nothing — reading it is your job.

### 1. Sort what you got into three piles

**Mechanical** — a dangling skill reference, a script nothing invokes, a
missing `allowed-tools`. One correct answer, no judgment. Offer to fix these
in the same turn.

**The docs are wrong** — the workspace does something the prose does not
describe. An undocumented repo, a branch prefix that no real task used. These
need a decision about *which side is wrong*: change the rule to match practice,
or change practice to match the rule. **Never assume the doc is right.** A rule
nothing has ever followed is a rule that lost, and the honest fix is usually to
update the doc.

**History** — `low` findings about past tasks (a log with no PRD, a branch
prefix in a closed task's log). These are records of what happened. Do not
rewrite them to satisfy a check. Say what they tell you about how the flow is
actually used, and move on.

### 2. Propose one change

Name the single finding worth acting on now, why it matters, and what the fix
touches. Prefer a finding that is currently costing a session something over
one that is merely untidy.

Do not propose fixing everything. This command exists to make the system better
by one increment per run; a sweep that rewrites six files is how a system
becomes something nobody trusts.

### 3. Fixing it

A change to `.claude/`, `CLAUDE.md` or `README.md` lands in **this** repo,
directly — spaces are worktrees of `repos/<service>`, and the system is not a
service. There is no space to create and no `/pr` to run.

Follow `ccs-conventions` for how the thing you are editing is meant to be
shaped. Before writing, re-read the file you are changing; these files are
mostly prose, and prose is the easiest thing in the workspace to make quietly
worse.

Then re-run `/ccs` and show the finding is gone. That delta is the evidence.

## mode: note

One line has been appended to `.claude/ccs-notes.md`. Confirm what was
recorded, in one sentence, and **return to whatever the session was doing.**

That brevity is the whole point. A note gets written mid-task, when friction is
fresh and the session has somewhere else to be. Do not open the notes file, do
not propose a fix, do not start a discussion about the system. The note is the
deliverable.

## mode: notes

Relay the open notes. If a note is now stale — the thing it describes has since
been fixed — say which and offer to tick it off. Group them if a theme is
obvious, but do not turn a list of eight lines into a roadmap.

## What does not belong here

- Anything about a service repo's code. That is a task; it needs a PRD and a space.
- Sweeping refactors of `.claude/`. One increment per run.
- Rewriting closed `space-log/` entries. Those are history, not documentation.
