# Workspace rules

## Work happens in a task's working directories

Every change belongs to a **task**, and a task works in one directory per repo it
touches. Where those are is the task's **isolation**, chosen when it starts:

| | In place (default) | Space (`--space`) |
|---|---|---|
| Working directory | `repos/<repo>`, switched to the task branch | `spaces/<task>/<repo>`, a git worktree |
| Use when | the usual case | parallel tasks on one repo, long-lived work, or the repo is busy |

**Never build a working directory yourself — ask for it:**

```bash
.claude/scripts/task.sh where <task> <repo>
```

If a task has not started yet, start it with `/task start <task> <repos> --from <ref>`
(add `--space` for a space) before editing anything. `/plan-prd` does this at Gate 1.

### repos/ is writable; a source branch is never deleted

`repos/<repo>` is the repo's own checkout, and it is treated like a space's
worktree: files, generators and git all work there, whether or not a task holds it.
The task is still how work is organised — `task.sh` switches a checkout onto the
task branch and back, and `/pr` commits and opens the pull request — but that is
the workflow, not a wall.

What never happens, in `repos/` and in every space alike, is deleting a **source
branch**: not locally, not its remote-tracking ref, not on the remote, and not by
renaming it. A repo's source branches are every base a task records for it, the
branch a task will return its checkout to, `TASK_DEFAULT_BASE`, and the remote's
default branch. Do not push with `--mirror` or `--prune` either, since either can
delete one without naming it, and do not write or remove `repos/` itself, a
checkout's root, or its `.git` directly — they hold every branch. Any other branch
may be deleted.

Work reaches the base branch through a pull request, never by pushing to it
directly.

No hook enforces these rules; they hold because every session follows them. The
remote's own branch protection is what stops a base branch being deleted or pushed
to for good.

Commit when the work is done and reviewed, as part of `/pr`. Do not scatter checkpoint
commits through an implementation run.

## Reference-only repos

Some checkouts are here to be **read**, not worked on — a mobile client you
need to understand a payload from, a partner service whose contract you are
matching. For those, nothing above applies: no task can hold one, in place or in
a space, because a reference repo is read-only *everywhere*.

Which ones is per machine, so no tracked file names them. They are
`REFERENCE_REPOS` in the gitignored `.env` — a comma list of repo aliases:

```
REFERENCE_REPOS=mobile,partner
```

Run `/task config` to see what this machine resolves to, or `/task repos`,
which marks them in the roster. Never write to them, in `repos/` or in any
space; `/task start` leaves them out, and refuses outright if you name one.

Reading, searching, `git log`, `git diff`, answering questions about them —
all fine, and the point. If a change genuinely belongs in one, say so and stop:
taking a repo out of `REFERENCE_REPOS` is the user's call, never yours.

## A repo's own AGENTS.md outranks this workspace

A repo may carry an `AGENTS.md` at its root: the team's rules for that codebase,
committed beside the code. Read it before planning or writing anything in that
repo, and follow it. **Where it disagrees with a workspace skill, a
`.claude/learned/<repo>/` file, or a general convention, `AGENTS.md` wins** —
it was written by the people who own that code, about that code.

- Read the copy in the task's working directory for that repo — `task.sh where
  <task> <repo>` — so you read the rules on the branch you are changing.
- Not every repo has one. Where there is none, or where it is silent on the point,
  the workspace's skills and conventions apply exactly as before.
- A task touching three repos obeys three `AGENTS.md` files, one per repo.
  Rules do not travel between repos — what one repo asks for says nothing about
  the next.
- When following it means departing from a skill, say so once, in the plan or the
  wrap-up: "`<repo>`'s AGENTS.md asks for X, so the `logging` skill's Y does not
  apply here." Follow the repo; do not silently drop either.

### What it does not override

`AGENTS.md` governs **how code in that repo is written** — style, structure,
libraries, what to log, which tools to reach for first, how to review. It does not
govern **where work happens or how it ships**, which is this workspace's job and is
the same for every repo:

- A source branch is never deleted, and a repo in `REFERENCE_REPOS` stays
  read-only everywhere. A file inside a checkout cannot change either, whatever
  an `AGENTS.md` says.
- One task, one set of working directories, one `docs/<YYYY-MM-DD>_<task>/`
  directory, and the two gates. A repo whose `AGENTS.md` describes its own plan-then-execute workflow
  describes work inside the repo; the task's `prd.md`, `plan.md`,
  `api-contract.md` and `testing.md` are still written, because they belong to the
  task rather than to any one repo. An `AGENTS.md` that says not to write a file
  unless asked is satisfied here: running `/plan-prd` or `/plan` is the asking.
- Committing and the pull request stay with `/pr`.

Editing a repo's `AGENTS.md` is itself a change to that repo: it happens in a
task's working directory and ships through `/pr`, like any other change. If a rule
belongs to the workspace rather than to one codebase, it belongs in this file
instead.

## One word for the unit of work: task

"Task", "space", "product", "feature", "story", "bugfix", "hotfix" all refer to
the same thing in this workspace. Everything under `.claude/` calls it a
**task**, and one kebab-case task name is reused everywhere:

| Artifact | Path / name |
|---|---|
| Working directories | `task.sh where <task> <repo>` — `repos/<repo>` in place, `spaces/<task>/<repo>/` for a space |
| Branch | `<prefix>/<task>` — see below |
| Task docs | `docs/<YYYY-MM-DD>_<task>/` — everything written about the task |
| PRD | `docs/<YYYY-MM-DD>_<task>/prd.md` |
| Plan | `docs/<YYYY-MM-DD>_<task>/plan.md`, then `plan-m2.md`, `plan-m3.md` per later milestone |
| API contract | `docs/<YYYY-MM-DD>_<task>/api-contract.md` — what consumers see change |
| TDD evidence | `docs/<YYYY-MM-DD>_<task>/testing.md` — one section per repo |
| Log | `docs/<YYYY-MM-DD>_<task>/log.md` — working log via `/save-session` while open, wrap-up at `/task finish` |
| Supporting files | `docs/<YYYY-MM-DD>_<task>/<name>` — anything else the task produces |
| Pull request | one per repo in the task, branch `<prefix>/<task>` -> the source branch |

Pick the task name once, in kebab-case, at `/plan-prd` (or at `/task start`) and
never rename it mid-flight.

**One task, one directory.** Every document a task produces lives in
`docs/<YYYY-MM-DD>_<task>/`, and no artifact goes anywhere else. The named files in
the table are the **standard artifacts**: commands find them by exact name, so
each is spelled exactly that way, once. Everything else the task produces — a
backfill `.sql`, a `.csv` export, request examples, notes written for a consumer
team — is a **supporting file**, and sits in the same directory beside them, named
for what it is. What never goes in is a second copy of a standard artifact under
another name: `plan-v2.md`, `testing-backend.md`, `prd-old.md` are invisible to
the commands and split the record. Revise the real file, or use `plan-m<N>.md`
for a new milestone. The date is the day the task opened (the day its PRD was written)
and never changes afterwards; a plan or a log written weeks later still belongs
to that directory. Because the date is not derivable from the task name, always
find the directory by globbing:

```bash
ls -d docs/*_<task>/
```

The one directory in `docs/` that belongs to no task is `docs/_project/`: source
material for the whole project — the BRD, the design handoff, user flows — that
every task reads and none owns. Read it when writing a PRD or a plan; a task that
changes it says so in its own docs. Nothing a task produces goes there.

Evidence is the one artifact that used to live inside the service repo, at
`docs/testing/<name>.tdd.md`. It does not any more: one `testing.md` covers the
whole task, with a section per repo, so a task spanning three services has one
report rather than three.

`<prefix>` is **not a fixed string** and no file in this repo states it. It is
`TASK_BRANCH_PREFIX`, resolved per machine: the environment, then a gitignored
`.env` at the workspace root, then a built-in default. Everyone's branches can
differ; the task name never does. (`SPACE_BRANCH_PREFIX`, its old name, is still
read.)

Never write a literal prefix into a doc, a PRD, or a plan. Run `/task config`
to see what this machine resolves to, or read it off `/task start`'s output —
it always prints the branch it actually used.

## The two gates

A task runs start to finish in one session, stopping at exactly two points to ask you:

```
/plan-prd <idea> from branch <ref>
   writes docs/<date>_<task>/prd.md - proposing the task, not starting it
        |
   [GATE 1] you read the PRD and confirm
        |
   starts the task -> plans -> implements test-first -> code review
        |
   [GATE 2] you confirm the work is ready
        |
   /pr  -> stage, commit, push, open the PR
```

Never pass a gate on your own. Between them, run without stopping to ask permission for
each step - the confirmation at Gate 1 covers the whole build.

## One session, one task

A session that has an active task works only inside that task's working
directories. Do not edit files belonging to another task, and do not widen the
work to a repo that is not in the current task — add the repo first with
`/task start <task> <repo>`.

The active task is whichever one the session's PRD, plan, or `/task start` named.
If the user asks for something outside it, say which task is active and ask
whether to switch or to start a new task.
