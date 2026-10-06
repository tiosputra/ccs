---
name: dev-deployment-note
description: Use when writing or reviewing the developer section of deployment notes for a list of pull requests - what each change does to production, whether anything breaks for a consumer, which config, secrets, migrations and third-party setup must be ready first, in what order to deploy, how to roll back and what survives a rollback, and what to watch afterwards. Also read by /deployment-notes, which uses the per-repo facts this skill learns - how config is provisioned, what deploys on merge, how migrations run, how to roll back.
metadata:
  origin: workspace
  learns: true
  fingerprint:
    - files deploy*.yml
    - files deploy*.yaml
    - files Dockerfile*
    - files docker-compose*.yml
---

# Dev Deployment Note

This file is the method: how to tell the developer who presses the button
everything they need to ship a set of pull requests safely, in any project. How
one repo reads its config, ships to production, runs migrations and rolls back
are facts about that repo, so they live in its learned file.

The QA section of the same notes is the `qa-release-note` skill's. This one
answers a different reader: not *what should be true afterwards*, but *what
must be done, in what order, and how to undo it*.

## Load the repo's facts first

For each repo in the release, start with its `AGENTS.md` if it has one, then:

```
.claude/scripts/learn.sh status dev-deployment-note
```

| State | Do |
|---|---|
| `fresh` | Read `.claude/learned/<repo>/dev-deployment-note.md` and follow it |
| `stale` | What it watches has moved. Run `/learn dev-deployment-note <repo>` before relying on it |
| `missing`, `unstamped` | Run `/learn dev-deployment-note <repo>` first, or say in the notes that the repo's config, deploy and rollback paths were not learned |

Where `AGENTS.md` and the learned file disagree, `AGENTS.md` wins. A deploy path
that was not learned is written as unknown, never as the common case.

## Lead with a verdict

The first thing a developer reads is one of three, with the reason in a line:

- **GO** - nothing below needs more than following the order.
- **GO WITH CONDITIONS** - name each condition: a key to set first, a window to
  deploy in, a PR to merge before another.
- **NO-GO** - a blocker: a failing check, an unmerged dependency, a breaking
  change with a consumer not yet updated, a migration that cannot run online.

Then a one-screen summary: repos, risk per repo (low, medium, high), and the
blast radius - who notices if this goes wrong, and how fast.

## Impact, per repo

Say what changes **in production behaviour**, not in code: which requests,
jobs, consumers or screens behave differently, for whom, and on what volume.
Name the money, auth or data paths a change crosses - those set the risk level.
A refactor that changes no behaviour says so in one line.

## Breaking changes

A change is breaking when something already deployed, or an app already
installed, stops working with it. Check every boundary the diff crosses:

- **API** - a removed or renamed endpoint or field, a changed type, a new
  required request field, a changed status code or error shape, a changed
  default, tighter validation.
- **Events and queues** - a renamed topic, a changed payload, a consumer that
  now rejects what the producer still sends.
- **Contracts copied between repos** (`proto` records) - a removed field or a
  reused field number breaks every copy, whether or not its repo is in the list.
- **Database** - a column dropped or renamed that another service, a report or
  a script still reads (`ddl` records).
- **Mobile** - an installed app cannot be redeployed. A response it depends on
  must keep working for every version still in use, not only the next one.

For each: who consumes it, whether that consumer is in this release, and the
**compatibility window** - how long old and new must run side by side. Where
nothing breaks, write `No breaking changes found` and the boundaries you
checked, so a reader can tell absence from not looking.

## Prepare before deploy

Everything that must exist before the code arrives, as a table a developer can
tick: what, which repo, which environments, who provides the value, and before
which step.

- **Config and secrets** (`env` records) - **read the file path, not just the
  key.** A key read where the repo reads service configuration (the learned file
  says where) goes into the deployment config of every environment. A key read
  by a one-off tool, a backfill or a script run by hand **must not**, even
  though it is new. Read the code for what happens when the key is missing: a
  service that refuses to boot is a deploy blocker; one that silently defaults
  is a production bug. Say which, and never write a secret's value.
- **Third parties** - a webhook URL to register, a callback to allow-list, a
  product or price to create in a provider's dashboard, a new API key.
- **Infrastructure** (`infra` records) - a changed build image, pipeline,
  container or manifest changes how the release itself ships. Say what is
  different about pressing the button this time.
- **Dependencies** (`dep` records) - pair each removal with its addition. Call
  out a major version, a new runtime requirement, and a library that touches
  money, auth or crypto. A patch bump needs no sentence.

## Data

- **Migrations** (`migration`, `ddl` records) - for each: does it lock a table
  that serves traffic, can the old code still run against the new schema during
  the rollout, and does it run before, with, or after the code (the learned file
  says how this repo runs them). A migration the old code cannot survive needs
  the expand-contract order: add, deploy code that writes both, backfill,
  switch reads, and remove only in a later release.
- **Manual steps** - a backfill, a script, a one-off fix: who runs it, against
  which environment, when, and whether it is safe to run twice.

## Deployment strategy

- **Order, with the reason for each step.** Producers before consumers,
  additive schema before the code that uses it, a backend before the app that
  calls it, a provider's setup before the code that expects it. Where order
  does not matter, say so.
- **What merging actually does**, per repo, from the `deploy` records and the
  learned file: merge deploys straight to production, deploys to a staging
  environment only, or deploys nothing until triggered. Never assume.
- **How it reaches traffic** - all at once, rolling, canary, or behind a flag -
  as the learned file records it. Where a flag exists, say its starting state.
- **When** - a quiet window for a risky change, and who must be around.

## Rollback

Per repo: the trigger (what you would see), the steps, and how to confirm it
worked. Then the part a code rollback does not cover:

- **Durable residue** - side effects that survive the rollback: codes already
  handed out, notifications already sent, payments already captured, rows
  written, data backfilled. Say explicitly what must **not** be cleaned up.
- **The point of no return** - a migration with no safe down, a data change, a
  message a third party has already received. Past that point, the plan is to
  fix forward; say so before the deploy, not during it.

## Verify after deploy

Concrete checks drawn from the diff, not a generic list: the endpoint to call,
the log line that proves the new path ran, the job that should run at its next
schedule, the error rate or queue depth to watch, and for how long. Say where
those logs and metrics live when the learned file records it.

## Risks, watch items and the previous notes

- List each risk with what would show it and who acts on it.
- **Read the previous deployment notes.** Carry forward its unresolved watch
  items, and flag any reversal - guidance given to another team that this
  release undoes is caught by nothing else.

## Writing it

- Developers read this with the PRs open, so PR numbers, repo names, file
  paths and keys are welcome here - the opposite of the QA section.
- Put a fact once and point at it; a deploy step stated twice drifts.
- Mark anything the records did not settle and the diff did not answer as an
  **open question for the release owner**, never as a guess.
