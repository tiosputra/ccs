---
description: Turn a stated list of pull requests into a deployment runbook with a QA-readable release note
argument-hint: "<name>, then the PR URLs one per line"
allowed-tools: Bash(.claude/scripts/release-notes.sh:*), Bash(.claude/scripts/learn.sh:*), Read, Write, Glob, Grep
---

## Arguments

```
/release-notes hotfix-m51

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

The output is one file, `release/<date>-<name>.md`: a deployment runbook whose
headline section is a **release note** — plain-language behavioural assertions
the user pastes to their QA team. The `qa-release-note` skill is how that note
is written; read it before writing one. If `release/` already holds a runbook,
the newest one is the house example — read it too.

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

## Your job

### 1. Run the roll call

Take the name from the first token and every `…/pull/<number>` URL from the rest
of the arguments, then:

```
.claude/scripts/release-notes.sh roll-call <name> "<url>" "<url>" …
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
.claude/scripts/learn.sh status qa-release-note
```

The `surface` and `deeplink` records come from each repo's learned
`qa-release-note` file. For a repo in the release whose row is `missing` or
`stale`, say so in one line and offer `/learn qa-release-note <repo>` — do not
start learning unasked. The app that routes links is usually a reference repo;
it can still be learned for this skill. Without learned facts the report still
runs; it prints a `learn` record where a surface would have been.

### 3. Gather

```
.claude/scripts/release-notes.sh report <name> <url...>
```

Records it prints, all tab-separated:

| Record | Meaning |
|---|---|
| `pr` | number, repo, state, head→base, size, files, review, merge state, failing checks, title |
| `missed` | open PR in a named repo that is not in the list |
| `env` | an env key an added line reads, **and the file it was read in** |
| `migration` | a migration file the PR adds |
| `deploy` | what merging actually does, per repo |
| `proto` | a changed contract file, and which other checkouts carry a copy |
| `deeplink` | a link an added line emits, checked against the app's learned route registry |
| `surface` | who a changed file faces, from the repo's learned surfaces |
| `learn` | a repo whose surfaces were not learned, so none are reported for it |
| `test` | an added or removed test assertion — the extraction engine |
| `gap` | a changed source file with no test touched in the same directory |

For anything the records do not settle — why a change was made, what it means
for the people using it — read the PR diff. One reader per repo is reasonable
for a large release; keep synthesis in this session.

To see what the script makes of one diff without `gh` — a saved diff, a PR you
are debugging — `release-notes.sh facts <org/repo> <diff-file>` prints the local
records alone.

### 4. Judge the records and extract the note

The script over-reports on purpose. The judgments — `env` by file path, `gap`
filtered to what someone could notice, `deeplink` by host, and turning `test`
records into the note by filtering, pairing, translating and adding unchanged
guards — are the `qa-release-note` skill's. Follow it, together with each repo's
learned file.

### 5. Write `release/<date>-<name>.md`

Sections, in this order:

1. At a glance — PR table, blockers, themes, blast radius
2. **Release note** — written per the `qa-release-note` skill
3. What changed, per repo
4. Cross-service contracts
5. Deploy order, with the `deploy` records as a "merging is deploying" table
6. Data work — migrations, and any manual step such as a backfill
7. External configuration — env keys, third parties, consumer apps
8. Rollback, **including durable residue**
9. Risks and watch items
10. Pre-deploy checklist and sign-offs
11. Post-deploy verification
12. Open questions for the release owner

Two of those are required rather than optional — rollback residue, and the diff
against the previous release note. The roll call prints `prev` for the latter.
The skill says what each must hold.

## What to refuse

- **Do not infer the PR list.** If the user names a milestone instead of URLs,
  ask for the URLs. There is no branch that identifies a release.
- **Do not read a local checkout for release facts**, and do not report a
  divergence, file count or commit from one.
- **Do not read a task's working directory for anything.** Architecture comes
  from the default branch.
- **Do not guess a surface or a route.** A repo with no learned facts gets a
  `learn` record; say so rather than inferring the audience from a folder name.
- **Do not merge, push, deploy, or trigger a workflow**, and do not offer to.
- **Do not invent a test assertion.** If a behaviour has no `test` record, mark
  it as untested — never write a plausible-sounding line as though extracted.
- If `gh` fails on a PR, say which one and stop. Do not retry with a different
  repo, a guessed number, or the local checkout.
