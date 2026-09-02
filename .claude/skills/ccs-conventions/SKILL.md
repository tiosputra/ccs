---
name: ccs-conventions
description: How this workspace's own machinery is built - the script/command split, how a slash command and a skill are shaped, the guard's real constraints, and the naming rules that keep one task one word. Use when creating or editing anything under .claude/, CLAUDE.md, or the workspace README - not when working on a service repo.
metadata:
  origin: swing
---

# ccs conventions

Rules for changing the workspace system itself: `.claude/commands/`,
`.claude/skills/`, `.claude/scripts/`, `CLAUDE.md`, `README.md`, and the
directory READMEs.

This is about the machinery, never about a service. Work on `backend`, `sport`,
`player`, `admin` or `payment` is a **task** — it needs a PRD, a space, and the
two gates. Work on the machinery lands in this repo directly, because a space is
a worktree of `repos/<service>` and the system is not a service.

## When to Activate

- Adding or editing a slash command, skill, script, or hook
- Editing `CLAUDE.md`, `README.md`, or a directory README
- Acting on a `/ccs` finding
- Wondering whether something should be a command, a skill, a script, or an agent

## The one architectural rule

> **Scripts hold facts. Commands hold judgment. Skills hold conventions.**

Everything under `.claude/` obeys this split, and most bad ideas here are a
violation of it.

| Layer | Holds | Never |
|---|---|---|
| `scripts/*.sh` | Deterministic facts: what git says, what is on disk, what a config declares. Read-only unless the whole point is to write | Decides anything. Never asks the user, never chooses a branch, never edits code |
| `commands/*.md` | What to do with those facts, and what to refuse | Restates a fact the script could print. Never re-derives what the script already computed |
| `skills/*/SKILL.md` | Standing conventions that apply whether or not a command ran | Contains a workflow with steps. That is a command |

**Why it matters:** anything a model writes from prose drifts between sessions.
A creation timestamp, a base commit, a file count — if a model produces it, each
session produces a slightly different shape. If a script produces it, it is the
same every time and can be diffed. So: **any fact that must be stable is a
script's output, not a paragraph of instructions.**

The corollary that catches people: when a command needs a new fact, the answer
is a new line in the script, not a new paragraph in the command.

## Choosing the shape

| You want | Build | Because |
|---|---|---|
| Deterministic facts about the workspace | a **script** | Same answer every run, diffable, testable with `bash -n` |
| A user-typed multi-step procedure | a **command** | `/name` is the trigger; it can eagerly run a script with `` !`…` `` |
| Rules that apply whenever a kind of file is touched | a **skill** | Auto-triggers from its `description`; no one has to remember it |
| The same procedure reachable without typing a command | a **skill** that routes to the script | Skills are model-triggered, commands are user-triggered |
| A hard rule that must hold even if a session ignores it | a **hook** | `guard.sh`. Prose is advice; a `PreToolUse` hook is enforcement |

**Almost never build an agent.** Agents start with no context and cannot write
back to the session that spawned them. Workspace bookkeeping needs exactly the
context the main session has — the task name, the PRD, the URL that just came
back from `gh`. The existing agents (`go-reviewer`, `typescript-reviewer`) earn
their place because review genuinely benefits from a fresh reading of a diff.
Nothing about managing the workspace does.

## Writing a command

```markdown
---
description: One line, imperative, what it does. Shown in the picker.
argument-hint: "add <task> [repos] | remove <task> | list"
allowed-tools: Bash(.claude/scripts/thing.sh:*), Read, Write
---

## Result

!`.claude/scripts/thing.sh slash $ARGUMENTS`

## What this is
…orientation for a session that has never run this before…

## Your job
…what to do with the result…
```

- **`!` runs eagerly, before the model reads anything.** So the script must be
  safe to run unconditionally. `space.sh slash remove` prints a *report* and
  removes nothing, precisely because the removal must not happen before the
  model has decided it is safe. Anything destructive gets a `slash` mode that
  only looks.
- **Dispatch on a `mode` line.** The script prints `mode<TAB>add` first; the
  command has a section per mode and the model follows the one that matches.
- **`allowed-tools` narrowly.** Without it every invocation prompts; too wide
  and the command can do things its prose never described.
- **Say what to refuse.** The best parts of `/space` and `/pr` are the "stop and
  report, do not retry with different flags" rules. A command that only says
  what to do will improvise when it fails.

## Writing a skill

- The **`description` is the whole trigger**. It is the only part read when
  deciding whether to load the skill, so it must name the artifacts and the
  moment: *"Use when writing or reviewing any className, style prop, .css
  file…"*. A description that describes the topic but not the trigger produces
  a skill that never fires.
- **`name:` must equal the directory name.** `/ccs` checks this.
- Conventions, not procedures. If it has numbered steps ending in an output, it
  is a command wearing a skill's clothes.
- Ground it in this codebase with real, measured numbers, and **say when they
  were measured**. A count that reads as current when it is eight months old is
  worse than no count.
- Do not pad to match the length of the imported `ECC` skills. Length is not the
  house style; those arrived that way.

## Writing a script

- `#!/usr/bin/env bash`, then a usage comment block that `usage()` prints back
  with `sed -n '3,20p'`. One source for the help text.
- **macOS ships bash 3.2.** No associative arrays, no `${var,,}`, no `mapfile`.
  Tab-separated lines and `awk` are the house workaround — see
  `space.sh`'s `BASE_OVERRIDES`.
- **`set -euo pipefail` for scripts that act; drop `-e` for scripts that
  report.** A health check that aborts on the first `grep` matching nothing
  reports less than nothing. `ccs.sh` says so in a comment where it drops it.
- **Output is data, not decoration.** `key<TAB>value` lines a model can read and
  a human can skim. Colors only when `[ -t 1 ]`.
- **Check everything before mutating anything.** `space.sh remove` validates
  every repo before touching the first, so a blocked teardown leaves the space
  whole instead of half gone.
- Add the script to `settings.json` `permissions.allow` so it does not prompt,
  and reference it from at least one command — `/ccs` flags scripts nothing
  invokes.

## Naming

One kebab-case **task** name is reused everywhere: space directory, branch,
PRD, plan, TDD evidence, wrap-up log. "Task", "space", "feature", "story",
"bugfix", "hotfix" are the same thing; `.claude/` says **task**.

The unit of work is a task. Do not introduce a second word for it, and do not
add a command named for a concept an existing command already owns — `/space`
owns spaces, so a `space-manager` beside it splits the concept in two.

**One task, one directory.** Everything written about a task lives in
`docs/<YYYY-MM-DD>_<task>/`: `prd.md`, `plan.md` (then `plan-m2.md`,
`plan-m3.md`), `testing.md`, `log.md`. If a new kind of task document comes
along, it becomes another file in that directory — never a new top-level
directory beside it, and never a copy inside a service repo. The date is the day
the task opened and never changes, so commands find a directory by globbing
`docs/*_<task>/` and never by reconstructing its name.

The one artifact that is easy to get wrong is the TDD evidence. `tdd-workflow`
is space-blind and writes wherever it is told; if nobody tells it, it writes
inside the service repo and the evidence ends up in that repo's pull request,
split per service. Whoever invokes it passes the report path.

## Settings are per machine, and no tracked file names one

Branch prefix and default base ref differ per person. They resolve through
`.claude/scripts/config.sh`, highest layer first:

| Layer | Where | For |
|---|---|---|
| environment | `SPACE_BRANCH_PREFIX=x space.sh add …` | a one-off |
| `.env` | workspace root, gitignored | your standing preference |
| built-in | the `cfg_resolve` fallback in the script | someone with no `.env` |

`.env.example` is the tracked template. Adding a setting means three edits:
`cfg_resolve NAME default` in the script that uses it, an entry in
`.env.example`, and nothing else — `/ccs` fails if the template falls behind
the scripts, or if anyone commits their own `.env`.

**Never write a literal prefix into a tracked file** — not a doc, not a PRD,
not a plan, not a report you print. It is correct only for its author. Docs
write `<prefix>/<task>`; `/ccs` flags any tracked file that hardcodes one.

When you need the real value, ask the workspace, never your memory:

```
/space config          what each setting resolved to, and which layer won
space.sh report <task> the branch a space is actually on
```

This is the same principle as the repo roster, and the general rule behind
both: **anything that varies per machine or over time is printed by a script,
never stated in prose.** A doc's job is to say where the value comes from.

One consequence worth knowing: changing your prefix does not rename branches
that already exist. A space created under an old prefix keeps working — every
command reads the branch from git — but `/space add` adding a repo to that
space will create a branch under the *new* prefix instead of joining the old
one. Finish a task under the prefix it started with.

## The guard is the only enforcement

`guard.sh` is a `PreToolUse` hook: `repos/` is read-only, no exceptions, and it
is not a matter of judgment. Everything else in `.claude/` is advice a session
can talk itself out of.

It reads command text rather than a parsed shell, so its precision is a design
choice rather than a guarantee. It aims to be exact in both directions: a write
that slips through is the obvious failure, but a read wrongly refused is a tax
on every session, and for a while it charged one.

What passes:

- Reading. `grep`, `find`, `cat`, `git log`, `git status`, `git diff`,
  `git show`, `git for-each-ref` against `repos/` all pass.
- **Redirects whose target is not inside a checkout.** `cd repos/backend && ls
  2>/dev/null` is fine, as are `2>&1`, `> /tmp/out`, and a write into
  `spaces/`. The guard resolves each redirect target against the directory the
  command `cd`-ed into, so only one that genuinely lands in `repos/` is refused.
- **Read-only forms of the dual verbs.** `branch`, `tag`, `worktree` and
  `stash` each have a form that only reports: `git -C repos/X branch --list`,
  `-a`, `--merged`, `--show-current`, `tag -l`, `worktree list`, `stash list`,
  and bare `git branch` / `git tag`. Their mutating forms — `branch -d`,
  `branch -m`, a bare new branch name, `worktree add`, `stash pop` — are
  blocked as before.
- **An ASCII arrow is not a redirect.** `->` and `=>` never introduce one in
  shell, so a heredoc or a printed line reading
  `spaces/x/backend -> repos/backend` passes.
- **`repos/README.md`.** It is tracked here (the gitignore un-ignores it) and
  describes the roster rather than living inside a checkout, so it is writable
  from a session. `repos/` itself, every `repos/<repo>/…` path, and a lookalike
  such as `repos/README.md.bak` stay sealed.
- `git add`/`commit`/`push` are expected inside a space and blocked in `repos/`.

Residual cases, still worked around rather than weakened — an over-eager guard
is the right failure direction:

- A **literal `> repos/backend/f.txt` inside a heredoc body** is still read as a redirect,
  because the guard does not track heredoc boundaries. Put that content in a
  file and run the file.
- Deep quoting, `eval`, and command substitution can still fool the text match
  either way. Nothing here is a substitute for not trying.

If you change the guard, run the full battery, not one payload — every
relaxation above is one a plausible regex change would undo silently. The
header comment carries a single hand-test payload for a smoke check. A guard
that exits non-zero on a malformed payload bricks the session, which is why it
fails open on anything unexpected — keep that property.

## Improving the system

`/ccs` reports what has drifted; `/ccs note <text>` records friction in the
moment it is felt. Both exist because system problems are discovered *during*
a task, when there is no room to fix them, and are gone by the time there is.

The rule is one increment per run. A system nobody trusts is one that changed
under them six files at a time.

When a `/ccs` finding says the docs and the workspace disagree, **check which
one reality is on** before assuming the doc wins. Sometimes the rule is what is
wrong; sometimes the rule is right and practice simply had not caught up.

Two design rules the checks themselves follow, worth keeping if you add more:

- **Never make a check that can only be satisfied by rewriting history.** Closed
  tasks' PRDs, plans and logs record what happened under whatever rule applied
  then. A task counts as closed once its directory holds a `log.md`, written
  just before teardown. The branch-prefix check skips those for that reason —
  otherwise it would report the same permanent findings forever, and the only
  way to silence it would be to falsify the record.
- **Prefer checking that a doc points at the truth over checking that it repeats
  it.** The repo roster is read from disk, so the check asks whether the docs
  send a reader to `/space repos` and whether they name a service that does not
  exist — not whether every service is listed. Nothing lists them, on purpose.
