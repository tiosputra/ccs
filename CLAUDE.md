# Workspace rules

## Git is allowed in spaces, never in repos/

`git add`, `git commit`, and `git push` are expected inside `spaces/<task>/<repo>/` -
`/pr` uses them to turn finished work into a pull request. What stays forbidden is
touching `repos/` at all. The guard hook enforces this; it is not a matter of judgment.

Commit when the work is done and reviewed, as part of `/pr`. Do not scatter checkpoint
commits through an implementation run.

## Writing on original repos is forbidden

`repos/<repo>` are canonical, read-only checkouts. Never create, edit, delete,
or run a code generator against a file under `repos/`. Reading is fine —
writing is not, and neither is `git checkout`, `git switch`, or any command
that moves a `repos/` checkout.

All work happens in a space worktree:

```
spaces/<task>/<repo>/
```

If a task has no space yet, create one with `/space add <task>` before editing
anything. If you find yourself about to write a path that starts with `repos/`,
stop and rewrite it as `spaces/<task>/...`.

## Reference-only repos

Some checkouts are here to be **read**, not worked on — a mobile client you
need to understand a payload from, a partner service whose contract you are
matching. For those, the escape hatch above does not apply: rewriting the path
as `spaces/<task>/...` does not make the edit allowed, because a reference repo
is read-only *everywhere*.

Which ones is per machine, so no tracked file names them. They are
`REFERENCE_REPOS` in the gitignored `.env` — a comma list of repo aliases:

```
REFERENCE_REPOS=mobile,partner
```

Run `/space config` to see what this machine resolves to, or `/space repos`,
which marks them in the roster. The guard hook reads the same setting and
refuses writes to `repos/<repo>/…` and `spaces/<task>/<repo>/…` alike; `/space
add` gives them no worktree, and refuses outright if you name one.

Reading, searching, `git log`, `git diff`, answering questions about them —
all fine, and the point. If a change genuinely belongs in one, say so and stop:
taking a repo out of `REFERENCE_REPOS` is the user's call, never yours.

## One word for the unit of work: task

"Task", "space", "product", "feature", "story", "bugfix", "hotfix" all refer to
the same thing in this workspace. Everything under `.claude/` calls it a
**task**, and one kebab-case task name is reused everywhere:

| Artifact | Path / name |
|---|---|
| Space (worktrees) | `spaces/<task>/<repo>/` |
| Branch | `<prefix>/<task>` — see below |
| Task docs | `docs/<YYYY-MM-DD>_<task>/` — everything written about the task |
| PRD | `docs/<YYYY-MM-DD>_<task>/prd.md` |
| Plan | `docs/<YYYY-MM-DD>_<task>/plan.md`, then `plan-m2.md`, `plan-m3.md` per later milestone |
| API contract | `docs/<YYYY-MM-DD>_<task>/api-contract.md` — what consumers see change |
| TDD evidence | `docs/<YYYY-MM-DD>_<task>/testing.md` — one section per repo |
| Wrap-up log | `docs/<YYYY-MM-DD>_<task>/log.md` |
| Pull request | one per repo in the space, branch `<prefix>/<task>` -> the source branch |

Pick the task name once, in kebab-case, at `/plan-prd` (or at `/space add`) and
never rename it mid-flight.

**One task, one directory.** Every document a task produces lives in
`docs/<YYYY-MM-DD>_<task>/` — no artifact goes anywhere else, and nothing else
goes in there. The date is the day the task opened (the day its PRD was written)
and never changes afterwards; a plan or a log written weeks later still belongs
to that directory. Because the date is not derivable from the task name, always
find the directory by globbing:

```bash
ls -d docs/*_<task>/
```

Evidence is the one artifact that used to live inside the service repo, at
`docs/testing/<name>.tdd.md`. It does not any more: one `testing.md` covers the
whole task, with a section per repo, so a task spanning three services has one
report rather than three.

`<prefix>` is **not a fixed string** and no file in this repo states it. It is
`SPACE_BRANCH_PREFIX`, resolved per machine: the environment, then a gitignored
`.env` at the workspace root, then a built-in default. Everyone's branches can
differ; the task name never does.

Never write a literal prefix into a doc, a PRD, or a plan. Run `/space config`
to see what this machine resolves to, or read it off `/space add`'s output —
it always prints the branch it actually created.

## The two gates

A task runs start to finish in one session, stopping at exactly two points to ask you:

```
/plan-prd <idea> from branch <ref>
   writes docs/<date>_<task>/prd.md - proposing the space, not creating it
        |
   [GATE 1] you read the PRD and confirm
        |
   creates the space -> plans -> implements test-first -> code review
        |
   [GATE 2] you confirm the work is ready
        |
   /pr  -> stage, commit, push, open the PR
```

Never pass a gate on your own. Between them, run without stopping to ask permission for
each step - the confirmation at Gate 1 covers the whole build.

## One session, one task

A session that has an active task works only inside that task's space. Do not
edit files belonging to another `spaces/<other-task>/`, and do not widen the
work to a repo that is not in the current space — add the repo to the space
first with `/space add <task> <repo>`.

The active task is whichever one the session's PRD, plan, or `/space add` named.
If the user asks for something outside it, say which task is active and ask
whether to switch or to open a new space.
