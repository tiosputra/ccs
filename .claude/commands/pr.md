---
description: "Stage, commit, push and open a pull request for a task's space — one PR per repo, based on the branch the space came from"
argument-hint: "[task] [base-branch] [--draft]"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

# Create Pull Request

The last step of a task. Everything before this leaves work uncommitted on purpose; this
command turns it into pull requests.

**Input**: `$ARGUMENTS` — all optional.

- a **task name**, if the session isn't already working one
- a **base branch**, overriding the branch the space was created from
- `--draft`

---

## Phase 0 — RESOLVE THE SPACE

A PR is per repo, but work is per space, so resolve the space first.

```bash
.claude/scripts/space.sh report <task>
```

If no task was given, use the one this session has been working. If the session has none
and there is more than one space, run `.claude/scripts/space.sh list` and ask which.

From the report take, per repo: `branch`, `base`, `uncommitted`, `unpushed`, and the
changed files. **The `base` line is the PR base** — that is the branch the space was
created from, and defaulting to `main` instead would open a PR against the wrong branch.
Strip the remote prefix for `gh`: `origin/feature/m5.1` becomes `feature/m5.1`. A base
branch in `$ARGUMENTS` overrides it.

Build the repo list: every repo in the space with `uncommitted > 0` or `unpushed > 0`.
Repos with nothing to ship are skipped and reported as skipped. If no repo has anything,
stop and say so — there is no PR to open.

Everything from here runs **once per repo in that list**, from inside
`spaces/<task>/<repo>/`.

---

## Phase 1 — VALIDATE

Per repo:

| Check | Condition | Action if failed |
|---|---|---|
| On the space's branch | `git branch --show-current` = `<prefix>/<task>` | Stop: report the actual branch, do not switch |
| Base branch exists | `git rev-parse --verify origin/<base>` succeeds | Stop: name the missing ref |
| Not based on itself | Current branch ≠ base | Stop: "branch and base are the same" |
| No existing PR | `gh pr list --head <branch> --json number` is empty | Report the existing PR number; push to it instead of creating a second |
| `gh` present and authed | `gh auth status` succeeds | Stop with the install or `gh auth login` hint |

---

## Phase 2 — DISCOVER

### Never stage an env file

`space.sh` copies `.env`, `.env.local`, `.env.development`, and `.env.*.local` into every
worktree so services can boot. They are untracked, so a bare `git add .` would commit
them. Before staging, list what is actually untracked:

```bash
git status --porcelain --untracked-files=all
```

Anything matching `.env*`, `*.pem`, `*.key`, `id_rsa*`, or `*credentials*` is **excluded
from the commit and reported as skipped**, even if the repo's `.gitignore` misses it.
If one of those files is already tracked in git, stop and tell the user rather than
committing a change to it.

### PR template

Search in order, first hit wins:

1. `.github/PULL_REQUEST_TEMPLATE/` — if it has several files, use `default.md` or ask
2. `.github/PULL_REQUEST_TEMPLATE.md`
3. `.github/pull_request_template.md`
4. `docs/pull_request_template.md`

### Change analysis

```bash
git status --short
git diff --stat
git diff <base-sha>..HEAD --stat        # if the space already has commits
```

Use the space report's `base` commit as the diff floor so the analysis covers committed
and uncommitted work together. Categorise changed files: source, tests, docs, config,
migrations.

### Planning artifacts

Everything written about the task lives in one directory at the workspace root. Find it
once, then read what is in it — it is the PR body's source material, and far better than
inferring intent from a diff:

```bash
ls -d docs/*_<task>/          # the date prefix is the day the task opened
```

- `docs/<date>_<task>/prd.md` — the problem, hypothesis, and milestone
- `docs/<date>_<task>/plan.md` (or `plan-m<N>.md`) — what was actually built
- `docs/<date>_<task>/testing.md` — the RED/GREEN evidence, one section per repo
- `docs/<date>_<task>/api-contract.md` — what consumers see change, if the task changed a boundary

These are workspace files, not repo files: read them from the workspace root, never from
inside the worktree, and never stage them. The evidence in particular **does not travel
with the PR** — no reviewer can open `testing.md` from GitHub — so the PR body's Testing
section has to carry the evidence itself. Lift that repo's section out of `testing.md`:
what is guaranteed, and the commands that prove it. A link alone is not enough.

The API contract travels the same way and for a sharper reason: its readers are the
frontend and mobile engineers reviewing this PR, and they cannot open a workspace path.
If `api-contract.md` exists and this repo is the provider, lift the entries this PR
implements into the body — the shapes, the nullability, and the error codes, not a
summary of them.

---

## Phase 3 — COMMIT

This is where the work becomes commits. Per repo, from its worktree root:

```bash
git add -A -- . ':(exclude).env*' ':(exclude)*.pem' ':(exclude)*.key'
git status --short          # show what is staged, before committing
git commit -m "<message>"
```

**Message** — conventional commit, derived from the PRD milestone and the plan, not from
the file list:

```
<type>(<scope>): <what changed, imperative, one line>

<why it changed — the PRD's problem statement in a sentence or two>

Task: <task>
Plan: docs/<date>_<task>/plan.md
```

`<type>` is `feat`, `fix`, `refactor`, `test`, `docs`, or `chore`. `<scope>` is the area
touched, not the repo name. If the repo's `AGENTS.md` sets its own commit-message or
prose conventions — a different subject form, no em dashes, no decorative characters —
follow them for that repo's commit and PR body; they outrank the shape above
(`CLAUDE.md`), and a task spanning two repos may write its message two ways. One commit per repo unless the work genuinely separates into
independent changes — do not split a single milestone into artificial commits.

Per this project's `CLAUDE.md`, do not add `Co-Authored-By` or generated-with trailers
unless the user asks for them.

The `Task:` and `Plan:` trailers stay here, on the commit, and travel no further — see
Phase 5. Anything the session's attribution rules append to a commit message
(`Co-Authored-By`, `Claude-Session`) is likewise a commit trailer only.

If `git commit` fails a pre-commit hook, report the hook's output and stop. Do not retry
with `--no-verify`.

---

## Phase 4 — PUSH

```bash
git push -u origin HEAD
```

If the remote has diverged:

```bash
git fetch origin
git rebase origin/<base>
git push --force-with-lease -u origin HEAD
```

Never plain `--force`. If the rebase conflicts, stop and hand it back — resolving someone
else's conflict silently is how work gets lost.

---

## Phase 5 — CREATE

### The body is not the commit message

A commit message and a PR body are written for different readers, and the trailers
belong to exactly one of them. **Nothing below ever appears in a PR body:**

```
Task: <task>                        <- commit trailer
Plan: docs/<date>_<task>/plan.md    <- commit trailer
Co-Authored-By: ...                 <- commit trailer, if any
Claude-Session: https://...         <- commit trailer, if any
🤖 Generated with ...               <- never, in either
```

Those lines are bookkeeping for the workspace, and half of them point at paths no
reviewer can open — `docs/<date>_<task>/` is workspace-local and is not in the repo.
A PR body ends with its last real section; it gets no trailer block and no footer.

Build the body from the sections below and from the planning artifacts. Never build
it by pasting or extending the commit message, and never reach for `gh pr create
--fill`, which turns the commit message *into* the body and drags every trailer with
it. Before running `gh pr create`, re-read the body you assembled and delete any line
matching the list above.

This bans trailers, not cross-references. The **Related** section is where a body
points outward, and links to the **sibling PRs in the same task are wanted** — they
are the only way a reviewer sees that a change spans several repos, and they resolve
on GitHub, which is what separates them from the lines above. Task docs get a mention
there too, in prose, marked workspace-local, so a reviewer knows that path is not
theirs to open.

### With a template

Fill in every section from the analysis and the planning artifacts. Preserve all sections;
write "N/A" rather than deleting one.

### Without a template

```markdown
## Summary

<1-2 sentences: what this does and why, taken from the PRD's problem and hypothesis>

## Changes

<bulleted, grouped by area>

## Testing

<this repo's section of testing.md, written out: what is guaranteed, and the commands
that prove it. Not a link - the file is not in this repo and the reviewer cannot open it.>

## API contract

<the entries of api-contract.md this PR implements, written out: request and response
shapes, nullability, enum values, error codes, socket delivery semantics. Omit the
section entirely when the PR changes nothing a consumer can observe.>

## Related

- Task docs: `docs/<date>_<task>/` — PRD, plan, contract, and evidence (workspace-local)
- Milestone <N>
- <sibling PRs in this task, if any>
```

### Open it

```bash
gh pr create --title "<title>" --base <base> --body "<body>"   # --draft if requested
```

Title = the commit's subject line for a single-commit PR; otherwise the milestone name
with a conventional-commit prefix.

### Multi-repo tasks

A space spanning several repos produces **one PR per repo**. Open them all, then edit each
body to link its siblings so a reviewer can see the set:

```bash
gh pr edit <number> --body "<body with sibling PR links>"
```

Say in each body which repo the PR belongs to and which order they should merge in, if
order matters.

---

## Phase 6 — VERIFY

Per PR:

```bash
gh pr view --json number,url,title,state,baseRefName,headRefName,additions,deletions,changedFiles
gh pr checks 2>/dev/null || true
```

---

## Phase 7 — OUTPUT

```
Task <task> — {n} pull request(s)

  #<number>  <repo>    <title>
             <url>
             <prefix>/<task> -> <base>   +<add> -<del> across <files> files
             checks: <status | none configured>

  #<number>  <repo>    ...

Skipped: <repo> — no changes
Not staged: <.env files excluded>, if any

Next:
  gh pr view <number> --web
  /code-review <number>
  /space remove <task>        after the PRs merge — writes the wrap-up log first
```

---

## Edge cases

- **No `gh` CLI**: stop — "GitHub CLI (`gh`) is required: https://cli.github.com/"
- **Not authenticated**: stop — "Run `gh auth login` first."
- **Nothing to commit anywhere**: stop — there is no PR to open.
- **Detached HEAD**: stop and report; do not check out a branch to fix it.
- **PR already open for the branch**: push to it and report the existing number rather than
  creating a duplicate.
- **Large PR (>20 files)**: note the size and, if the changes separate cleanly, say how —
  but still open it. Splitting is the user's call.
- **Repo is not in the space**: never `cd` into `repos/`. That is the read-only origin and
  the guard hook will block it; the PR comes from the worktree.
