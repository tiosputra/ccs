---
description: Review one Rust repo of a task by hand - hands its working directory and base commit to the rust-reviewer agent
argument-hint: "<task> <repo>"
allowed-tools: Bash(.claude/scripts/task.sh report *), Read, Agent
---

## Result

!`.claude/scripts/task.sh report $ARGUMENTS`

## What this is

A hand-run entry point to `rust-reviewer`, for a Rust repo of a task outside
`/plan-prd`'s review step - a second look after a fix, or a review of a task built
before the repo had a reviewer. Inside `/plan-prd` nothing here is needed: its review
step dispatches `rust-reviewer` for any repo with a `Cargo.toml` at its root.

The agent is layout-blind. It is handed a working directory and a base commit, never a
task name; this command reads both off `task.sh report` above.

## Your job

1. Take `$ARGUMENTS` as `<task> <repo>`. If either is missing, or the report above is an
   error, say so and stop - do not guess a task, and do not build a path yourself.
2. From the `repo` block for that repo, take `workdir` (relative to the workspace root -
   make it absolute) and the commit on the `base` line.
3. Check the working directory has a `Cargo.toml` at its root. If it does not, it is not
   a Rust repo: say which reviewer `/plan-prd` would use instead and stop.
4. Dispatch `rust-reviewer` with: the absolute working directory, the base commit, the
   path to the repo's `AGENTS.md` if it has one, and the task's `testing.md`
   (`tasks/*_<task>/testing.md`) if it has a section for this repo, so the agent reads
   the suite's result instead of rerunning it.
5. Relay the findings ranked CRITICAL, HIGH, MEDIUM. Do not fix anything unless the user
   asks; the agent never writes, and neither does this command.

## Refuse

- A repo in `REFERENCE_REPOS` - `task.sh report` will not list it; nobody's code there is
  ours to review.
- A repo or path that no task holds. Start the task first with `/task start`.
