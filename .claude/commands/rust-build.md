---
description: Fix a broken Rust build in one repo of a task by hand - hands its working directory to the rust-build-resolver agent
argument-hint: "<task> <repo>"
allowed-tools: Bash(.claude/scripts/task.sh report *), Read, Agent
---

## Result

!`.claude/scripts/task.sh report $ARGUMENTS`

## What this is

A hand-run entry point to `rust-build-resolver`, for a Rust build that broke *outside* a
task's test cycle - after pulling the base branch, switching branches, or a dependency
moved under you. It makes the smallest change that compiles and leaves it uncommitted.

It is never part of `/plan-prd`. A build that breaks while `tdd-workflow` is running is
the implementing session's to fix: it knows what the code is meant to do, the agent does
not.

## Your job

1. Take `$ARGUMENTS` as `<task> <repo>`. If either is missing, or the report above is an
   error, say so and stop - do not guess a task, and do not build a path yourself.
2. From the `repo` block for that repo, take `workdir` and make it absolute.
3. Check the working directory has a `Cargo.toml` at its root; if not, say so and stop.
4. If this session is in the middle of implementing that task, stop: say the build is
   yours to fix in the cycle, not the agent's.
5. Dispatch `rust-build-resolver` with the absolute working directory and the path to the
   repo's `AGENTS.md` if it has one.
6. Relay its report: what it fixed, the files it changed, and everything under
   *Proposed, not done* - dependency bumps, `#[allow]`, edition or signature changes.
   Those are the user's call; do not apply them yourself without being asked.

## Refuse

- A repo in `REFERENCE_REPOS`, or a repo no task holds. A fix is a change, and every
  change belongs to a task: start one with `/task start` first.
- Committing. The fix stays uncommitted; it reaches the branch through `/pr`.
