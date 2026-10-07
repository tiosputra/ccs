---
description: Turn a stated set of branches into deployment notes - each service's feature branch compared against its target from local snapshots - a dev section on what to prepare, the order and how to roll back, then a QA release note
argument-hint: "<name>, then one line per service: <service> -> <feature> -> <target>"
allowed-tools: Bash(.claude/scripts/deployment-notes.sh:*), Bash(.claude/scripts/learn.sh:*), Bash(git diff:*), Read, Write, Glob, Grep, Artifact
---

## Arguments

```
/deployment-notes gsa

api -> feature/gsa -> main
billing -> feature/gsa -> main
app -> hotfix/checkout-copy -> main
```

The name is the first token. Then one line per service: the checkout alias under
`repos/`, the branch that ships, the branch it ships into. Blank lines, `- `
bullets and `→` arrows are all fine. Branches always mean the branch **on
origin**: `origin/feature/gsa` and `feature/gsa` are the same input, and a local
branch of that name is never looked at. One line per service — if two branches ship
into one service, name the branch that carries both.

**This command deliberately has no eager-run block.** Every other command here
opens with one, so its absence looks like an omission — it is not. That syntax
expands the arguments into a single shell command string, and these arguments
are multi-line, so it fails the permission check before anything runs. Do not
add one back. Run the script yourself, as step 1 below, passing each line as its
own quoted argument.

## What this is

A release is **whatever branches the user names**. Nothing infers it, and
nothing should try: one wave routinely merges a feature branch into several
repos and, the same day, hotfix branches straight into the same base, while an
app ships on a scheme of its own.

The changes are read **from code, not from a pull request**. A hosted PR diff
gives up past a size limit, and a release branch is exactly the diff that hits
it. So for each service the script asks origin what both branches point at
(`git ls-remote` — the server, not the local clone), fetches exactly those
commits, refuses if the fetched ref is anything else, and exports them side by
side, two directories per service — three services, six directories:

```
release/<date>-<name>/
  api-target/         main as it is now — what production runs
  api-feature/        feature/gsa — what it will run
  api.diff            main...feature/gsa, from the merge base — the PR's view, no limit
  api.files           the same as numstat — where to start reading
  manifest.tsv        the exact SHAs compared; every fact in the notes is about these
  <date>-<name>.md    the notes (step 5)
  <date>-<name>.html  the notes as a page, and artifact.url, where it is published (step 6)
```

They are plain exports, not worktrees and not task spaces: no `.git`, nothing to
commit from, gitignored under `release/`. Nothing in `repos/` changes except the
remote-tracking refs the fetch updates.

**A release usually ships while the app is on TestFlight.** The services go to
production first; the app build that uses the new behaviour is still in
TestFlight, and the store builds people have installed keep talking to the same
production. So every release must stay **backward compatible** with installed
app versions, the TestFlight build and the web at the same time. Anything that
is not is the first thing the notes say. The app checkout is usually a reference
repo: read it at its default branch for what an installed app does with a
response, and say how old that checkout is.

The output is one file, `release/<date>-<name>/<date>-<name>.md`, inside the
snapshot directory: deployment notes for two readers, in this order. It is also
published as a page (step 6), so it can be read and shared without the repo.

| Section | Reader | Asks | Written per |
|---|---|---|---|
| **Dev** | whoever ships it | What must be ready, in what order, how do I undo it? | `dev-deployment-note` skill |
| **QA** | the QA team | What should be true afterwards? | `qa-release-note` skill |

Read both skills before writing. If `release/` already holds notes, the newest
file is the house example — read it too. Notes written before this command was
split have the QA note near the top and the deploy material spread after it;
follow the section list below, not their order.

## Rules that are not matters of judgment

**Every release fact comes from the snapshot, and the snapshot comes from
origin.** What changed, how big, which files — from `<svc>.diff`, `<svc>.files`
and the two directories, which hold the SHAs origin reported, recorded in
`manifest.tsv`. Never from a checkout's working tree, a local branch, or a
remote-tracking ref you did not just see the script confirm — not
`git diff main..feature/gsa` in `repos/`, not `git log origin/main` without a
fetch. If origin cannot confirm a branch, the script stops and writes nothing;
do not fall back to whatever ref is already there.

**Open pull requests are context, not the source.** The script lists them, when
`gh` works, to catch a duplicate or forgotten PR into the same target. Their
diffs are never read for the notes.

**Never read a task's working directory for a release.** Whether it is a space
under `spaces/` or a checkout an in-place task holds, it carries one task's
unfinished work, not the service. Architecture of a repo that is not in the
release comes from its default branch: `git -C repos/<repo> show origin/HEAD:<path>`.

**Never edit the snapshot directories.** They are evidence. Re-running `prepare`
replaces them whole.

**Never merge, deploy, or trigger a workflow.** This command writes only inside
its release directory - the notes, the page, the artifact link - and publishes
that page. If the user asks it to merge, say what would deploy on merge and stop.

**Never write a secret's value.** The notes name a key, where it is set and who
provides it — never what it is, even when the diff or a config file shows it.

## Your job

### 1. Prepare the snapshot

Take the name from the first token and every `<service> -> <feature> -> <target>`
line from the rest, then:

```
.claude/scripts/deployment-notes.sh prepare <name> "<service> -> <feature> -> <target>" …
```

One quoted argument per line — never paste the raw multi-line block into the
shell. If the arguments carry no such line, ask for them and stop. An `error`
line means nothing was written: report it as printed and stop — do not guess a
branch name, swap a service, or retry with a different spelling.

It prints, per service:

| Record | Fields |
|---|---|
| `svc` | service, feature, feature SHA, target, target SHA, commits ahead, commits behind, files, +added/-deleted |
| `source` | the GitHub repo, and `origin/<branch>@<sha>` for both sides — the provenance line for the notes |
| `snapshot` | the target directory, the feature directory, the diff, the numstat |
| `pr` | the open PR from that feature into that target, if one exists — number, review, merge state, title |
| `missed` | another open PR into the same target that is not part of this release |

Then **tell the user, in one short paragraph, before the expensive read**:

- any service whose feature is **behind** its target. The diff is from the merge
  base, so it still shows exactly what the feature brings, but the merge has not
  been rehearsed against what the target gained since — a conflict risk to
  name in the notes. It also means a file-by-file comparison of the two
  directories shows those commits as reverts, so take what changed from
  `<svc>.diff`, and use the directories for context;
- any service with **nothing ahead** — nothing to release there;
- the `missed` PRs, for awareness. Duplicate PRs carrying content already inside
  the release, with squash merge on, land the same content twice under new SHAs,
  so the user should know they exist — but they are listed, never treated as a
  blocker. PR state (open, unreviewed, blocked, missing) never is.

Do not stop for approval; they may ignore it.

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
.claude/scripts/deployment-notes.sh report <name>
```

It reads the newest snapshot for that name — no fetch, so the notes describe the
SHAs in `manifest.tsv` and nothing else. It does ask origin whether either
branch has moved since: a `moved` record (service, `origin/<branch>`, snapshot
SHA, SHA now) means the snapshot is stale — tell the user and re-run `prepare`
before writing, unless they say to write against the snapshot as it is. Records
it prints, all tab-separated, with the service alias as the second field:

| Record | Meaning | Section |
|---|---|---|
| `svc` | the roll call again, as `prepare` recorded it | both |
| `moved` | origin's branch is no longer the SHA in the snapshot | — |
| `diff-lines` | how large each service's diff is | — |
| `env` | an env key an added line reads, **and the file it was read in** | dev |
| `migration` | a migration file the feature adds | dev |
| `ddl` | a statement in an added migration that locks, breaks old code, or changes data — with why | dev |
| `dep` | a dependency line added or removed in a manifest; a `-` and `+` on one name is a bump | dev |
| `infra` | a changed build, pipeline, container or manifest file | dev |
| `deploy` | each workflow a push to the target sets off, each deploy workflow that runs only by hand, or `none` | dev |
| `proto` | a changed contract file, and which other checkouts carry a copy | dev |
| `deeplink` | a link an added line emits, checked against the app's learned route registry | QA |
| `surface` | who a changed file faces, from the repo's learned surfaces | QA |
| `learn` | a repo whose surfaces were not learned, so none are reported for it | QA |
| `test` | an added or removed test assertion — the extraction engine | QA |
| `gap` | a changed source file with no test touched in the same directory | QA |

For anything the records do not settle — why a change was made, what it means
for the people using it, what happens when a new key is missing — **read the
code**. Start from `<svc>.files`, largest and least generated first (skip
lockfiles and generated code), read the hunks in `<svc>.diff`, and open the
whole file in `<svc>-feature/` beside its old self in `<svc>-target/` when a hunk
needs its context. To narrow a large diff to one path:

```
git diff --no-index release/<date>-<name>/<svc>-target/<path> release/<date>-<name>/<svc>-feature/<path>
```

Mind the `behind` count before doing that across a whole directory. One reader
per service is reasonable for a large release; keep synthesis in this session.

To see what the script makes of one diff on its own,
`deployment-notes.sh facts <service> <diff-file>` prints the local records alone.

### 4. Judge the records

The script over-reports on purpose. The records marked **dev** are judged by
the `dev-deployment-note` skill: an `env` key by the file that reads it, a `ddl`
line by whether the old code survives it, a `dep` pair by whether the bump
matters. The records marked **QA** are the `qa-release-note` skill's: `gap`
filtered to what someone could notice, `deeplink` by host, and `test` records
turned into the note by filtering, pairing, translating and adding unchanged
guards. Follow each repo's learned files for both.

### 5. Write `release/<date>-<name>/<date>-<name>.md`

A header with the name, the snapshot time, and a table of the services in scope —
feature and target with their SHAs, ahead/behind, size, and the open PR if one
exists — then:

1. **At a glance** — the verdict (GO, GO WITH CONDITIONS, NO-GO) and why in a
   line, judged on the code alone; themes; blast radius; the other open PRs
   into each target, for awareness
2. **Dev — deploying it**, per the `dev-deployment-note` skill:
   1. Impact, per repo
   2. **Backward compatibility** — store builds, the TestFlight build, the
      web and other services, as a table per change; or `No breaking changes
      found`, with what was checked
   3. **Deploy steps** — one numbered runbook in the order the work happens:
      config, third-party setup, data to seed, scripts, sheet edits, branches to
      bring up to date, migrations, merges and deploys. Each step says why it
      sits there and what breaks if it is skipped
   4. Reference for the steps — config and secrets, third parties,
      migrations, manual scripts, dependencies, a "what merging into the
      target sets off" table from the `deploy` records, how it reaches traffic
   5. Rollback, **including durable residue** and the point of no return
   6. Verify after deploy
   7. Risks and watch items — about the code's behaviour, carried forward from
      the previous notes
   8. Sign-offs
3. **QA — release note**, per the `qa-release-note` skill. Self-contained, so
   it can be pasted whole
4. **Open questions for the release owner**
5. **How this was produced** — the `origin/<branch>@<sha>` pairs compared, the
   snapshot time, what was not learned, and the diff against the previous notes

Three things are required rather than optional: the verdict, rollback residue,
and the diff against the previous notes. Both modes print `prev` for the
last of those. The skills say what each must hold.

### 6. Publish the notes as a page

```
.claude/scripts/deployment-notes.sh page <name>
```

It builds `<date>-<name>.html` beside the notes - the markdown embedded and
rendered in the browser, with a contents rail and a copy button on code blocks,
so the QA note can be pasted whole - and prints `page`, `title` and
`artifact-url` (`-` when it was never published).

Publish that file with the Artifact tool:

- `artifact-url` is `-`: publish `file_path` = the page, with `icon: "checklist"`
  and a one-sentence `description` naming the release and its verdict. Write
  the URL it returns into `release/<date>-<name>/artifact.url`, alone on one
  line.
- otherwise: publish the same file with `url` = that URL, no `icon`, so the
  link people already have keeps working.

Run `page` and republish every time the notes change. Never edit the HTML by
hand - it is rebuilt from the notes, and the notes are the record.

### 7. Leave the snapshot

Give the user the artifact link and say where the snapshot is. It is what a
reviewer opens to check a claim in the notes, so do not remove it unasked;
`deployment-notes.sh clean <name>` removes the exports and keeps the notes, the
page and the link.

## What to refuse

- **Do not assume an installed app copes with a change.** Read what it does
  with the response, and treat the store build and the TestFlight build as two
  clients of the same production.
- **Do not make a blocker of PR state or of work the team does.** An open,
  unreviewed or missing PR, a duplicate PR, config to set, rows to seed, a script
  to run, a sheet to edit, a conflict to resolve — the first are listed for
  awareness, the rest are deploy steps. Do not ask, check or report whether a
  step has been done; the notes describe the release, not the team's progress.

- **Do not infer the branch list.** If the user names a milestone, a PR, or
  "everything on dev", ask for the `<service> -> <feature> -> <target>` lines.
- **Do not read a release fact from anywhere but the snapshot** — not a local
  branch, not a working tree, not a PR's hosted diff — and do not report a file
  count or commit from one.
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
- If `prepare` cannot confirm or fetch a branch from origin, say which and stop.
  Do not retry with a different branch, a guessed name, or the ref already on
  disk.
