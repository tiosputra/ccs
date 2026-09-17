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

## A repo's own AGENTS.md outranks this workspace

A repo may carry an `AGENTS.md` at its root: the team's rules for that codebase,
committed beside the code. Read it before planning or writing anything in that
repo, and follow it. **Where it disagrees with a workspace skill, a
`.claude/learned/<repo>/` file, or a general convention, `AGENTS.md` wins** —
it was written by the people who own that code, about that code.

- Read the copy in the checkout you are working in, `spaces/<task>/<repo>/AGENTS.md`.
  A space is a worktree, so it carries its own; the one under `repos/` is the same
  file, but reading it is not the habit to build.
- Not every repo has one. Where there is none, or where it is silent on the point,
  the workspace's skills and conventions apply exactly as before.
- A task touching three repos obeys three `AGENTS.md` files, one per worktree.
  Rules do not travel between repos — what `player` asks for says nothing about
  `web`.
- When following it means departing from a skill, say so once, in the plan or the
  wrap-up: "`<repo>`'s AGENTS.md asks for X, so the `logging` skill's Y does not
  apply here." Follow the repo; do not silently drop either.

### What it does not override

`AGENTS.md` governs **how code in that repo is written** — style, structure,
libraries, what to log, which tools to reach for first, how to review. It does not
govern **where work happens or how it ships**, which is this workspace's job and is
the same for every repo:

- `repos/` stays read-only, and a repo in `REFERENCE_REPOS` stays read-only
  everywhere. A file inside a checkout cannot grant write access to that checkout;
  the guard hook enforces this whatever an `AGENTS.md` says.
- One task, one space, one `docs/<YYYY-MM-DD>_<task>/` directory, and the two
  gates. A repo whose `AGENTS.md` describes its own plan-then-execute workflow
  describes work inside the repo; the task's `prd.md`, `plan.md`,
  `api-contract.md` and `testing.md` are still written, because they belong to the
  task rather than to any one repo. An `AGENTS.md` that says not to write a file
  unless asked is satisfied here: running `/plan-prd` or `/plan` is the asking.
- Committing and the pull request stay with `/pr`.

Editing a repo's `AGENTS.md` is itself a change to that repo: it happens in that
repo's space and ships through `/pr`, never by writing into `repos/`. If a rule
belongs to the workspace rather than to one codebase, it belongs in this file
instead.

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
| Supporting files | `docs/<YYYY-MM-DD>_<task>/<name>` — anything else the task produces |
| Pull request | one per repo in the space, branch `<prefix>/<task>` -> the source branch |

Pick the task name once, in kebab-case, at `/plan-prd` (or at `/space add`) and
never rename it mid-flight.

**One task, one directory.** Every document a task produces lives in
`docs/<YYYY-MM-DD>_<task>/`, and no artifact goes anywhere else. The named files in
the table are the **standard artifacts**: commands find them by exact name, so
each is spelled exactly that way, once. Everything else the task produces — a
backfill `.sql`, a `.csv` export, request examples, notes written for the mobile
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
