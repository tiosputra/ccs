---
description: Turn a stated list of pull requests into deployment notes - a dev section on what to prepare, the order and how to roll back, then a QA release note
argument-hint: "<name>, then the PR URLs one per line"
allowed-tools: Bash(.claude/scripts/deployment-notes.sh:*), Bash(.claude/scripts/learn.sh:*), Read, Write, Glob, Grep
---

## Arguments

```
/deployment-notes hotfix-m51

https://github.com/<org>/<repo>/pull/1053
https://github.com/<org>/<other-repo>/pull/599
```

The name is the first token. The pull requests follow, one per line — blank
lines, `- ` bullets and trailing slashes are all fine.

**This command deliberately has no eager-run block.** Every other command here
opens with one, so its absence looks like an omission — it is not. That syntax
expands the arguments into a single shell command string, and these arguments
are multi-line, so it fails the permission check before anything runs. Do not
add one back. Run the script yourself, as step 1 below, passing each URL as its
own quoted argument.

## What this is

A release is **whatever pull requests the user names**. Nothing infers it, and
nothing should try: one wave routinely merges a feature branch into several
repos and, the same day, hotfix branches straight into the same base, while an
app ships on a scheme of its own. There is no identifier a script could resolve.

The output is one file, `release/<date>-<name>.md`: deployment notes for two
readers, in this order.

| Section | Reader | Asks | Written per |
|---|---|---|---|
| **Dev** | whoever ships it | What must be ready, in what order, how do I undo it? | `dev-deployment-note` skill |
| **QA** | the QA team | What should be true afterwards? | `qa-release-note` skill |

Read both skills before writing. If `release/` already holds notes, the newest
file is the house example — read it too. Notes written before this command was
split have the QA note near the top and the deploy material spread after it;
follow the section list below, not their order.

## Rules that are not matters of judgment

**Every release fact comes from `gh`.** State, size, checks, diffs and file
lists come from the pull requests. A local checkout is only as fresh as its last
fetch, and a stale one has reported a repo as having nothing to release, and a
22-file change against a real 51. The script reads `repos/` only for slow-moving
architecture — deploy workflows, contract copies, an app's route registry — and
always at the repo's default branch, never from a working tree a task may have
moved.

**Never read a task's working directory for a release.** Whether it is a space
under `spaces/` or a checkout an in-place task holds, it carries one task's
unfinished work, not the service. When you need architecture the script did not
print, read it at the default branch: `git -C repos/<repo> show origin/HEAD:<path>`.

**Never merge, deploy, or trigger a workflow.** This command reads and writes
one file. If the user asks it to merge, say what would deploy on merge and stop.

**Never write a secret's value.** The notes name a key, where it is set and who
provides it — never what it is, even when the diff or a config file shows it.

## Your job

### 1. Run the roll call

Take the name from the first token and every `…/pull/<number>` URL from the rest
of the arguments, then:

```
.claude/scripts/deployment-notes.sh roll-call <name> "<url>" "<url>" …
```

One quoted argument per URL — never paste the raw multi-line block into the
shell. If the arguments carry no URL, ask for them and stop.

It prints one `pr` line per URL, an `alias` line mapping each repo to its
checkout under `repos/` (or `-`), and, under `missed`, other open PRs into the
same base that the user did **not** name.

Those `missed` lines matter. Duplicate PRs carrying content already inside the
release PRs, with squash merge on, land the same content twice under new SHAs —
that has been the top blocker of a release before. **Surface the missed list to
the user before the expensive read**, in one short paragraph. Do not stop for
approval; they may ignore it.

### 2. Check what has been learned

```
.claude/scripts/learn.sh status dev-deployment-note
.claude/scripts/learn.sh status qa-release-note
```

Each skill learns its own facts per repo: `dev-deployment-note` how a repo is
configured, deployed, migrated and rolled back; `qa-release-note` who its paths
face and where the app routes links — the script's `surface` and `deeplink`
records come from that one. For a repo in the release whose row is `missing` or
`stale` in either, say so in one line and offer `/learn <skill> <repo>` — do not
start learning unasked. The app that routes links is usually a reference repo;
it can still be learned for `qa-release-note`. Without learned facts the notes
still get written; say in the section concerned which facts were not learned.

### 3. Gather

```
.claude/scripts/deployment-notes.sh report <name> <url...>
```

Records it prints, all tab-separated:

| Record | Meaning | Section |
|---|---|---|
| `pr` | number, repo, state, head→base, size, files, review, merge state, failing checks, title | both |
| `missed` | open PR in a named repo that is not in the list | at a glance |
| `env` | an env key an added line reads, **and the file it was read in** | dev |
| `migration` | a migration file the PR adds | dev |
| `ddl` | a statement in an added migration that locks, breaks old code, or changes data — with why | dev |
| `dep` | a dependency line added or removed in a manifest; a `-` and `+` on one name is a bump | dev |
| `infra` | a changed build, pipeline, container or manifest file | dev |
| `deploy` | what merging actually does, per repo | dev |
| `proto` | a changed contract file, and which other checkouts carry a copy | dev |
| `deeplink` | a link an added line emits, checked against the app's learned route registry | QA |
| `surface` | who a changed file faces, from the repo's learned surfaces | QA |
| `learn` | a repo whose surfaces were not learned, so none are reported for it | QA |
| `test` | an added or removed test assertion — the extraction engine | QA |
| `gap` | a changed source file with no test touched in the same directory | QA |

For anything the records do not settle — why a change was made, what it means
for the people using it, what happens when a new key is missing — read the PR
diff. One reader per repo is reasonable for a large release; keep synthesis in
this session.

To see what the script makes of one diff without `gh` — a saved diff, a PR you
are debugging — `deployment-notes.sh facts <org/repo> <diff-file>` prints the
local records alone.

### 4. Judge the records

The script over-reports on purpose. The records marked **dev** are judged by
the `dev-deployment-note` skill: an `env` key by the file that reads it, a `ddl`
line by whether the old code survives it, a `dep` pair by whether the bump
matters. The records marked **QA** are the `qa-release-note` skill's: `gap`
filtered to what someone could notice, `deeplink` by host, and `test` records
turned into the note by filtering, pairing, translating and adding unchanged
guards. Follow each repo's learned files for both.

### 5. Write `release/<date>-<name>.md`

A header with the name, scan date, the repos in scope and the PR table, then:

1. **At a glance** — the verdict (GO, GO WITH CONDITIONS, NO-GO) and why in a
   line, blockers, the `missed` PRs, themes, blast radius
2. **Dev — deploying it**, per the `dev-deployment-note` skill:
   1. Impact, per repo
   2. Breaking changes — or `No breaking changes found`, with what was checked
   3. Prepare before deploy — config and secrets, third parties,
      infrastructure, dependencies
   4. Data — migrations, and any manual step such as a backfill
   5. Deployment strategy — order with reasons, a "merging is deploying" table
      from the `deploy` records, how it reaches traffic, when
   6. Rollback, **including durable residue** and the point of no return
   7. Verify after deploy
   8. Risks and watch items, carried forward from the previous notes
   9. Pre-deploy checklist and sign-offs
3. **QA — release note**, per the `qa-release-note` skill. Self-contained, so
   it can be pasted whole
4. **Open questions for the release owner**
5. **How this was produced** — the PRs read, what was not learned, and the diff
   against the previous notes

Three things are required rather than optional: the verdict, rollback residue,
and the diff against the previous notes. The roll call prints `prev` for the
last of those. The skills say what each must hold.

## What to refuse

- **Do not infer the PR list.** If the user names a milestone instead of URLs,
  ask for the URLs. There is no branch that identifies a release.
- **Do not read a local checkout for release facts**, and do not report a
  divergence, file count or commit from one.
- **Do not read a task's working directory for anything.** Architecture comes
  from the default branch.
- **Do not guess a surface, a route, or a deploy path.** A repo with no learned
  facts is reported as unlearned; say so rather than inferring the audience from
  a folder name or the pipeline from a common case.
- **Do not merge, push, deploy, or trigger a workflow**, and do not offer to.
- **Do not invent a test assertion.** If a behaviour has no `test` record, mark
  it as untested — never write a plausible-sounding line as though extracted.
- **Do not write a secret's value**, a production hostname's credentials, or
  customer data into the notes.
- If `gh` fails on a PR, say which one and stop. Do not retry with a different
  repo, a guessed number, or the local checkout.
