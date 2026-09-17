---
description: Learn how one repo does what a skill covers, and write it down once so later sessions read it instead of re-scanning
argument-hint: "[status] [skill] | <skill> <repo>"
allowed-tools: Bash(.claude/scripts/learn.sh:*), Read, Write, Edit, Glob, Grep
---

## Result

!`.claude/scripts/learn.sh slash $ARGUMENTS`

## What this is

A skill that learns is split in two. `SKILL.md` is the **method**: how to do
the thing well in any codebase, with no repo or library named. What applying
it to one repo takes (which logger, which test runner, which trap) is **learned**
once, into `.claude/learned/<repo>/<skill>.md`, and every later load reads that
instead of re-deriving it from the code.

`learn.sh` owns the facts about those files: whether one exists, when it was
learned, and whether the code it watches has changed since. This command is
the judgment in between, which covers reading a repo and writing down what is true of it.

```
/learn                     every learning skill x every workable repo
/learn logging             one skill, every repo
/learn logging backend     scan backend, write .claude/learned/backend/logging.md
```

The first line of the result says which `mode` ran.

## mode: status

Rows are `learned<TAB>skill<TAB>repo<TAB>state<TAB>date<TAB>reviewed<TAB>fingerprint`.

| state | Meaning | What to say |
|---|---|---|
| `fresh` | Watched code unchanged since learning | Nothing to do |
| `stale` | Something the file watches has changed | Offer `/learn <skill> <repo>` |
| `unstamped` | Written but never stamped | Run the `stamp` line, then check again |
| `missing` | Never learned | Offer `/learn <skill> <repo>` |

`unreviewed` is separate from state: a scan is a first draft, and nobody has
confirmed this one. Point those out, since reading one takes a minute and a
wrong fact in it misleads every session after.

Relay the table grouped by what needs doing. Do not start learning anything
unasked.

## mode: learn

### 1. Read before scanning

- **The repo's `AGENTS.md`, if it has one.** It is the team's own statement of
  how this repo works, and it outranks whatever the scan concludes: where the
  code and the file disagree, the file is the rule and the code is what has not
  caught up. Do not copy it into the learned file — point at it, and record only
  what it does not say.
- `discover` is the skill's checklist: what to look for, how to search without
  the misses earlier scans made, and **the exact shape of the file to write**.
  Follow its headings; a learned file in some other shape is one the next
  session cannot rely on.
- If `learned_file` already exists, read it. You are refreshing, not rewriting.
  A human edit in it is a correction a scan once missed, so keep it unless the
  code now plainly says otherwise, and say so if you drop one.

### 2. Scan `repo_dir`, read-only

It is a canonical checkout under `repos/`, readable and never writable. Search,
read, `git log`; never edit, never generate into it.

**Measure, do not estimate.** Every number in the file comes from a command you
ran in this scan. Say what you searched when the answer is "none found", so a
reader can tell absence from not looking.

### 3. Write `learned_file`

- The frontmatter shape is in `discover`. Leave `learned:` and `fingerprint:`
  as `pending`; the script fills them.
- Where the repo has an `AGENTS.md`, say so at the top of the file and note which
  of its sections cover this skill, so a later session reads the rule rather than
  the scan of it. A measured habit that its rules forbid is a trap to name, not a
  pattern to record.
- `watch:` lists what the scan found this repo's facts rest on (the dependency
  line, the wrapper file, the middleware mount). Where the repo has an
  `AGENTS.md`, watch it too — `files AGENTS.md` — so a rewrite of the rules makes
  the scan stale, which is the point: the rules outrank it. Keep it narrow: watching all
  of `go.mod` makes every dependency bump look like a change, and a status that
  is always stale gets ignored.
- `reviewed: no`, always. Only the user sets `yes`.
- No repo facts go into `SKILL.md`. If the scan shows the method itself is
  wrong or missing a rule, say so separately; that is a `/ccs` matter.

### 4. Stamp it

Run the `stamp` line from the result. It writes today's date and the
fingerprint, the two values a model must never produce itself. Then run
`.claude/scripts/learn.sh status <skill>` and show the row is `fresh`.

### 5. Report

Five lines at most: what the repo uses, anything that surprised you, and which
facts you are least sure of. Ask the user to read the file. When they say it
is right, set `reviewed: yes` and nothing else. The fingerprint does not cover
that line, so it stays fresh.

## mode: error

Relay the message. Do not retry with a guessed skill or repo name; the message
lists what exists.

## What does not belong here

- Writing anything under `repos/` or a space. The learned file lives in `.claude/learned/`.
- Learning a skill that does not declare `learns: true`. Make it a learning skill first, per `ccs-conventions`.
- Changing code to match what you found. Learning describes the repo; fixing it is a task.
