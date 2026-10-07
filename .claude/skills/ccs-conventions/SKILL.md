---
name: ccs-conventions
description: How this workspace's own machinery is built - the script/command split, how a slash command and a skill are shaped, why no hook enforces the rules, and the naming rules that keep one task one word. Use when creating or editing anything under .claude/, CLAUDE.md, or the workspace README - not when working on a service repo.
metadata:
  origin: workspace
---

# ccs conventions

Rules for changing the workspace system itself: `.claude/commands/`,
`.claude/skills/`, `.claude/scripts/`, `CLAUDE.md`, `README.md`, and the
directory READMEs.

This is about the machinery, never about a service. Work on any repo under
`repos/` is a **task** — it needs a PRD, a task started with `/task`, and the
two gates. Work on the machinery lands in this repo directly, because a task
works in `repos/<repo>` (or a worktree of it) and the system is not a repo there.

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
| A user-typed multi-step procedure | a **command** | `/name` is the trigger; it can eagerly run a script by putting a bang directly before a backticked command |
| Rules that apply whenever a kind of file is touched | a **skill** | Auto-triggers from its `description`; no one has to remember it |
| The same procedure reachable without typing a command | a **skill** that routes to the script | Skills are model-triggered, commands are user-triggered |
| A hard rule that must hold even if a session ignores it | not a hook — see *No hook enforces the rules* | Put it on the remote (branch protection) or in `permissions.deny` |

**Almost never build an agent.** Agents start with no context and cannot write
back to the session that spawned them. Workspace bookkeeping needs exactly the
context the main session has — the task name, the PRD, the URL that just came
back from `gh`. The reviewers (`go-reviewer`, `typescript-reviewer`,
`react-reviewer`, `flutter-reviewer`, `database-reviewer`, `security-reviewer`) earn their place
because review genuinely benefits from a fresh reading of a diff.
`tdd-guide` earns its place differently: it runs one repo's `tdd-workflow` cycle
so a multi-repo milestone can run its repos in parallel. It carries no method of
its own — it reads the skill — and it returns its evidence rather than writing a
shared file. The build resolvers (`go-build-resolver`, `dart-build-resolver`)
are outside the flow on purpose: a build broken mid-cycle is the implementing
session's to fix, so they are run by hand, for a build broken by a pull or a
branch switch. `code-reviewer` is the review step's fallback, for a diff no
language reviewer covers. `planner` and `architect` are read-only and run by hand:
a fresh, independent reading is the point, so they return a draft or a set of
options and the session writes the plan or the ADR. Nothing about managing the
workspace benefits from an agent.

An agent imported from elsewhere is adapted before it is used, the way these
were: it is handed one working directory and stops without one, it names the
skill it follows instead of restating a method, it says what it may write and
that it never commits, and its `description` says when the flow calls it —
never "use PROACTIVELY", which pulls sessions off the flow. `/ccs` checks the
last part: no description says `PROACTIVELY` or `MUST BE USED`, and every agent
is named by a command or says it is run by hand.

## Writing a command

```markdown
---
description: One line, imperative, what it does. Shown in the picker.
argument-hint: "start <task> [repos] | finish <task> | list"
allowed-tools: Bash(.claude/scripts/thing.sh:*), Read, Write
---

## Result

BANG`.claude/scripts/thing.sh slash $ARGUMENTS`

## What this is
…orientation for a session that has never run this before…

## Your job
…what to do with the result…
```

- **A leading bang runs eagerly, before the model reads anything.** So the
  script must be safe to run unconditionally. `task.sh slash finish` prints a
  *report* and releases nothing, precisely because the finish must not happen
  before the model has decided it is safe. Anything destructive gets a `slash`
  mode that only looks.

  `BANG` in the template above stands for that literal character. A real one in
  this file would run every time the skill loads - which is the bug this wording
  avoids.
- **Dispatch on a `mode` line.** The script prints `mode<TAB>start` first; the
  command has a section per mode and the model follows the one that matches.
- **`allowed-tools` narrowly.** Without it every invocation prompts; too wide
  and the command can do things its prose never described.
- **Say what to refuse.** The best parts of `/task` and `/pr` are the "stop and
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
  `task.sh`'s `BASE_OVERRIDES`.
- **`set -euo pipefail` for scripts that act; drop `-e` for scripts that
  report.** A health check that aborts on the first `grep` matching nothing
  reports less than nothing. `ccs.sh` says so in a comment where it drops it.
- **Output is data, not decoration.** `key<TAB>value` lines a model can read and
  a human can skim. Colors only when `[ -t 1 ]`.
- **Check everything before mutating anything.** `task.sh finish` validates
  every repo before touching the first, so a blocked finish leaves the task
  whole instead of half released. The same goes for metadata: `task.sh` writes a
  task's record only when its first repo actually joins.
- Add the script to `settings.json` `permissions.allow` so it does not prompt,
  and reference it from at least one command — `/ccs` flags scripts nothing
  invokes.
- **JavaScript under `scripts/` is held to the same rule.** A library imported from
  elsewhere (`scripts/lib/*.js`, with its tests in `.claude/tests/`) counts as reached
  only when something outside that library and its tests calls it — a chain of files
  requiring each other, with tests that pass, is still unused. `/ccs` runs
  `node --check` on each and flags the ones with no outside caller.

## Skills that learn: method and facts

A skill that needs facts about a repo is split, so the method travels to any
project and the facts are measured once per repo instead of on every load:

| Part | Where | Holds |
|---|---|---|
| method | `skills/<skill>/SKILL.md` | How to do it well anywhere. Names no repo, service, or in-house library |
| checklist | `skills/<skill>/discover.md` | What to find in a repo, how to search without known misses, the exact output shape |
| facts | `.claude/learned/<repo>/<skill>.md` | What is true of one repo. Gitignored, learned per machine |
| rules | `<repo>/AGENTS.md` | What that repo's team requires. Theirs, committed with their code, and outside this workspace |

- The frontmatter declares it: `learns: true`, plus `fingerprint:` entries under
  `metadata` that name generic things worth watching. The learned file adds
  its own `watch:` list for what that repo's facts rest on.
- `learn.sh` holds the facts about the facts: fresh, stale, unstamped or
  missing, and it stamps the date and fingerprint. `/learn` does the scan. It
  is the same split as everywhere else.
- `SKILL.md` opens with a section that loads the repo's rules and facts, and
  ranks them: `AGENTS.md`, then the learned file, then the skill — each winning
  only where it actually speaks. A skill that prescribes how code is written says
  so even when it does not learn; `CLAUDE.md` is the full statement, the skill
  just has to not contradict it.
- **`AGENTS.md` is the repo's, not ours.** Never write one from here, never
  restate one inside a skill or a learned file, and never mirror a rule out of one
  into `.claude/` — a copy drifts the moment the team edits theirs, and then the
  workspace is confidently wrong. Point at the file.
- **A repo or service name in a learning skill's `SKILL.md` is a fact that leaked
  into the method.** Move it to the learned file.
- Workspace glue is a third kind, neither method nor fact: working directories,
  gates, where `testing.md` goes. It belongs in the command that invokes the
  skill, the way `/plan-prd` hands `tdd-workflow` its working directory and report
  path.
- **No skill or agent names a path layout or a repo.** Not `spaces/`, not
  `repos/<name>`, not `space.sh`; a skill is handed a working directory and works
  there. `/ccs` flags a skill or agent that names a repo this machine knows — a
  checkout under `repos/`, or one something was learned about.
- A skill that describes a repo rather than code written in it — who a path
  faces, where an app routes links — may learn reference-only repos too. It
  says so with `learns-reference: true` beside `learns: true`; `qa-release-note`
  does, because the app that routes links is usually a reference repo. Every
  other skill leaves reference repos out, since nobody writes code there.
- Not every skill learns. One or two facts do not earn a learned file and a
  fingerprint; a repo's own `AGENTS.md` is enough. When a team writes down what a
  learned file had been guessing, the learned file gets shorter, not longer.

## Naming

One kebab-case **task** name is reused everywhere: branch, metadata, space
directory when it has one, PRD, plan, TDD evidence, wrap-up log. "Task",
"space", "feature", "story", "bugfix", "hotfix" are the same thing; `.claude/`
says **task**, and "space" means only the `--space` isolation. In place is the
only default, deliberately not a setting: a task gets a space when, and only when,
someone types `--space`.

The unit of work is a task. Do not introduce a second word for it, and do not
add a command named for a concept an existing command already owns — `/task`
owns tasks, so a `task-manager` beside it splits the concept in two.

**Where a task's work lives is decided in one place.** `tasklib.sh` turns a task
and a repo into a working directory; `task.sh where` prints it; every command,
script and hand-off asks rather than building `repos/<repo>` or
`spaces/<task>/<repo>` itself. A new script that needs a task's files sources
`tasklib.sh`, whose header documents the metadata format.

**One task, one directory.** Everything written about a task lives in
`docs/<YYYY-MM-DD>_<task>/`. The standard artifacts have fixed names that
commands find them by: `prd.md`, `plan.md` (then `plan-m2.md`, `plan-m3.md`),
`api-contract.md`, `testing.md`, `log.md`. Anything else a task produces — SQL,
CSV, examples, notes for another team — is a supporting file beside them, free to
name. A new kind of task document is another file in that directory — never a new
top-level directory beside it, and never a copy inside a service repo. A command
that starts reading a supporting file by name has made it a standard artifact:
add it to the list, to `CLAUDE.md`, and to `/ccs`'s `check_artifacts`. The date is the day
the task opened and never changes, so commands find a directory by globbing
`docs/*_<task>/` and never by reconstructing its name. The one directory beside
the task directories is `docs/_project/`, for source material the whole project
shares (a BRD, a design handoff); `check_artifacts` skips it, and nothing a task
produces belongs there.

The one artifact that is easy to get wrong is the TDD evidence. `tdd-workflow`
is layout-blind and writes wherever it is told; if nobody tells it, it writes
inside the service repo and the evidence ends up in that repo's pull request,
split per service. Whoever invokes it passes the report path.

## Settings are per machine, and no tracked file names one

Branch prefix, default base ref and reference repos differ per person. They
resolve through `.claude/scripts/config.sh`, highest layer first:

| Layer | Where | For |
|---|---|---|
| environment | `TASK_BRANCH_PREFIX=x task.sh start …` | a one-off |
| `.env` | workspace root, gitignored | your standing preference |
| built-in | the `cfg_resolve` fallback in the script | someone with no `.env` |

`.env.example` is the tracked template. Adding a setting means three edits:
`cfg_resolve NAME default` in the script that uses it, an entry in
`.env.example`, and nothing else — `/ccs` fails if the template falls behind
the scripts, or if anyone commits their own `.env`. Renaming one uses
`cfg_resolve_renamed NEW OLD default`, which keeps reading the old name, so no
machine's `.env` breaks on a pull.

**Never write a literal prefix into a tracked file** — not a doc, not a PRD,
not a plan, not a report you print. It is correct only for its author. Docs
write `<prefix>/<task>`; `/ccs` flags any tracked file that hardcodes one.

When you need the real value, ask the workspace, never your memory:

```
/task config           what each setting resolved to, and which layer won
task.sh report <task>  the branch and working directory a task is actually on
```

This is the same principle as the repo roster, and the general rule behind
both: **anything that varies per machine or over time is printed by a script,
never stated in prose.** A doc's job is to say where the value comes from.

One consequence worth knowing: changing your prefix does not rename branches
that already exist. A task started under an old prefix keeps working — its
metadata records its branch, and adding a repo to it reuses that branch. Only a
new task picks up the new prefix.

## No hook enforces the rules

The workspace once had `guard.sh`, a `PreToolUse` hook over `Write`, `Edit` and
`Bash` that judged every command by matching regexes against its raw text. It
was removed on 2026-09-30. Do not rebuild it without answering what went wrong:

- **It could not fail open.** The hook ran ~450 lines of Python inside a
  single-quoted `python3 -c '…'`. One apostrophe in a comment ended the string,
  bash exited 2 on the syntax error, and exit 2 is the code a hook uses to
  *block* — so every Bash, Edit and Write call in every session was refused,
  including the edit that would have fixed it.
- **Its precision was a regex over shell text.** Reads were refused as writes
  (`2>/dev/null` after a `cd`, `git branch --list`, an ASCII arrow in a heredoc,
  a `$VAR` redirect target), and each fix added more rules to get wrong.

The rules it enforced are still rules — `CLAUDE.md` states them — and are kept
the way every other rule here is: by sessions following them. Where one must
hold even if a session does not, put it where it cannot brick a session:

- **Base branches**: branch protection on the remote. It stops a deletion or a
  direct push from anyone, not only from an agent.
- **Reference repos**: optionally, per-machine `permissions.deny` entries such
  as `Edit(repos/mobile/**)` in the gitignored `.claude/settings.local.json`.

If a hook is ever added again: keep its logic in its own file (a `.py`, never a
quoted string), have the wrapper allow on any exit other than a deliberate
block, and have `/ccs` syntax-check it.

### The one hook there is: it informs, never gates

`SessionStart` runs `scripts/session-start.sh`, added 2026-10-06. It prints the
open tasks that have a saved working log (`task.sh logs`), so a new session knows
`/resume-session` has something to load — ECC's session-start hook, kept to the one
thing this workspace needed from it. It is shaped by everything `guard.sh` got wrong:

- **Its logic is a script in `scripts/`**, so `/ccs` parses it like any other.
- **It cannot block.** The script exits 0 on every path, and `settings.json` wraps the
  call in `; exit 0` too. `/ccs` fails any hook whose command does not end that way.
- **It reads facts, it does not derive them.** What counts as an open log is
  `tasklib.sh`'s `log_closed` and `log_last_saved`, the same functions `ccs.sh`
  uses; the hook only formats them.

A new hook that would decide anything — refuse a command, rewrite an edit — is a
gate, and the section above applies to it in full.

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
  then. A task counts as closed once its `log.md` records a `Closed` date, which
  `/task finish` writes just before the task finishes — an open task's log, kept
  by `/save-session`, carries `Closed: —`. The branch-prefix check skips those for that reason —
  otherwise it would report the same permanent findings forever, and the only
  way to silence it would be to falsify the record.
- **Prefer checking that a doc points at the truth over checking that it repeats
  it.** The repo roster is read from disk, so the check asks whether the docs
  send a reader to `/task repos` and whether they name a repo that is not
  checked out — not whether every repo is listed. Nothing lists them, on
  purpose. Docs write `repos/<repo>`, never a real name.
