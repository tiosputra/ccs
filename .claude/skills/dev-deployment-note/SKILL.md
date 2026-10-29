---
name: dev-deployment-note
description: Use when writing or reviewing the developer section of deployment notes for a stated set of changes - feature branches compared against their target, or pull requests - what each change does to production, whether it stays backward compatible with installed app versions while the new build is still in beta (TestFlight), which config, secrets, migrations and third-party setup must be ready first, in what order to deploy, how to roll back and what survives a rollback, and what to watch afterwards. Also read by /deployment-notes, which uses the per-repo facts this skill learns - how config is provisioned, what deploys on merge, how migrations run, how to roll back.
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
everything they need to ship a set of changes safely, in any project. How
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

The first thing a developer reads is one of three, with the reason in a line.
The verdict judges **the code being shipped**, nothing else:

- **GO** - the change is safe to ship by following the deploy steps in order.
- **GO WITH CONDITIONS** - the code is safe only under a constraint the steps
  cannot express by order alone: a window to deploy in, a feature to keep
  switched off, an app version that must be released first.
- **NO-GO** - the code itself is wrong for production: a breaking change with a
  consumer not yet updated, a migration that cannot run online, a deploy order
  that cannot be satisfied.

What never moves the verdict:

- **Pull request state.** An open, unreviewed or missing PR, its checks, and
  other open PRs into the same target are the team's workflow, not a property
  of the release. List other open PRs for awareness, never as a blocker.
- **Work the team does as part of the deploy** - config to set, rows to seed, a
  script to run, a dashboard to repoint, a sheet column to insert, a branch to
  bring up to date. Those are **deploy steps** (below). Write them as steps;
  never as blockers or conditions, and never ask or check whether they have
  been done.

Then a one-screen summary: repos, risk per repo (low, medium, high), and the
blast radius - who notices if this goes wrong, and how fast.

## The release header

The section opens the way the team's release document does - a table a release
owner can fill and paste:

- **Release date** - left for the release owner; never invented.
- **Branch** - in place of a category: each service's feature branch and the
  target it ships into. A release is its branches, so the branch says more than
  a label like "New Feature" would.
- **Participants** - the people who wrote the code, from the commit authors
  between the merge base and the feature SHA, per service, most commits first.
  Names only, never an email; one person under two emails is one participant.
- **PRD** - a link where a task's PRD describes the branch, otherwise blank.
- **Google Meet** - blank, for the owner.
- **Pull requests** - each PR with its state, and the release date column
  left for the owner.

## Summary of request change

Everything a reader needs if they read nothing else: the features in the
release as a plain list, one line each, then the verdict and risk per repo,
then a **must prepare** callout - how many new env keys and in which services,
how many migrations, what data must exist in the database, what third-party
setup and manual scripts there are, and whether anything breaks an installed
app - each pointing at the subsection that holds the detail.

## Make what must be prepared impossible to miss

New config and required data are the steps most often missed at a release, so
they get their own subsections, marked with ⚠️ in the heading, not rows buried
in a reference table:

- **New environment variables**, per service: a block ready to paste into the
  deployment config, one `KEY=` line each with a placeholder that says where the
  value comes from - never the value - and beside it what happens when it is
  missing (refuses to boot, or silently defaults), whether it is new or must be
  checked because it may already exist, and anything to double-check, such as a
  port or a host that differs per environment.
- **Migration / seeder / DML**, per service: how this repo runs them, every
  file, what each does, whether it locks a table or breaks the old code.
- **Required database data**: rows that must exist before the code that reads
  them runs - master data, config rows, a feature flag kept in a table. Each
  says the table, why it is needed, what breaks without it, and a read-only
  query that shows whether it is there. Never customer data.

## Impact, per repo

Say what changes **in production behaviour**, not in code: which requests,
jobs, consumers or screens behave differently, for whom, and on what volume.
Name the money, auth or data paths a change crosses - those set the risk level.
A refactor that changes no behaviour says so in one line.

## Backward compatibility

Services usually reach production **before** the app build that uses them is
public - it is still in a beta channel (TestFlight, internal testing) when the
services ship. Production then serves every client at once, and must keep
working for each of them:

- **the store builds people have installed** - every version still in use,
  not only the latest. An installed app cannot be redeployed, so it never
  learns about the change;
- **the beta build**, which is the one exercising the new behaviour - against
  production;
- **the web**, and **other services** that call the changed ones.

So a release is backward compatible by default, and anything that is not must
be called out first. Check every boundary the diff crosses:

- **API** - a removed or renamed endpoint or field, a changed type, a new
  required request field, a changed status code or error shape, a changed
  default, tighter validation, a **new value in a field an app switches on**
  (a status, a type, an error code the old app has no branch for).
- **Version gates** - where the code picks behaviour by app version, say what
  each version gets, what a request **with no version** gets, and confirm the
  old builds take the path they took before.
- **Events and queues** - a renamed topic, a changed payload, a consumer that
  now rejects what the producer still sends.
- **Contracts copied between repos** (`proto` records) - a removed field or a
  reused field number breaks every copy, whether or not its repo is in the list.
- **Database** - a column dropped or renamed that another service, a report or
  a script still reads (`ddl` records).

Read the app's own code where it decides what it does with a response - the
status values it handles, the fields it requires - rather than assuming it
copes. Write the result as a table: each change, what the store build sees,
what the beta build sees, and the web. Where nothing breaks, write `No breaking
changes found` and the boundaries you checked, so a reader can tell absence
from not looking.

## Deploy steps

One numbered runbook, in the order the work happens, from the first thing to
prepare to the last service deployed. Each step says what to do, in which repo
or system, why it sits at that point, and what goes wrong if it is skipped or
done out of order. A developer follows it top to bottom; nothing else in the
notes should be needed to ship.

Everything the team does goes in it as a step - preparing config, seeding data,
running a script, registering a webhook, inserting a sheet column, resolving a
merge conflict, running a migration, merging or triggering a deploy. Do not
turn a step into a question about whether it was done, and do not gate the
verdict on it.

**Order, with the reason for each step.** Producers before consumers, additive
schema before the code that uses it, a backend before the app that calls it, a
provider's setup before the code that expects it. Where order does not matter,
say so.

Reference subsections sit beside the runbook so a step can point at them. Config,
migrations and required data are judged as below and written into their ⚠️
subsections; the rest go together under the notes:

- **Config and secrets** (`env` records) - **read the file path, not just the
  key.** A key read where the repo reads service configuration (the learned file
  says where) goes into the deployment config of every environment. A key read
  by a one-off tool, a backfill or a script run by hand **must not**, even
  though it is new. Read the code for what happens when the key is missing: a
  service that refuses to boot, or one that silently defaults into a production
  bug. Say which, and never write a secret's value.
- **Third parties** - a webhook URL to register, a callback to allow-list, a
  product or price to create in a provider's dashboard, a new API key.
- **Infrastructure** (`infra` records) - a changed build image, pipeline,
  container or manifest changes how the release itself ships. Say what is
  different about pressing the button this time.
- **Dependencies** (`dep` records) - pair each removal with its addition. Call
  out a major version, a new runtime requirement, and a library that touches
  money, auth or crypto. A patch bump needs no sentence.
- **Migrations** (`migration`, `ddl` records) - for each: does it lock a table
  that serves traffic, can the old code still run against the new schema during
  the rollout, and does it run before, with, or after the code (the learned file
  says how this repo runs them). A migration the old code cannot survive needs
  the expand-contract order: add, deploy code that writes both, backfill,
  switch reads, and remove only in a later release.
- **Manual work** - a backfill, a script, a one-off fix: against which
  environment, when, and whether it is safe to run twice. An optional script
  is an optional step, marked so.
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

- List each risk with what would show it and who acts on it. A risk is about
  the code's behaviour in production. A skipped deploy step is not a risk entry;
  its consequence belongs in the step.
- **Read the previous deployment notes.** Carry forward its unresolved watch
  items, and flag any reversal - guidance given to another team that this
  release undoes is caught by nothing else.
- Write a watch item so it can be checked: the endpoint, page or signal, and
  what healthy looks like. `canary-watch` runs those checks after the deploy.

## Writing it

- Developers read this with the code open, so branch names, commit SHAs, PR
  numbers, repo names, file paths and keys are welcome here - the opposite of the QA section.
- Put a fact once and point at it; a deploy step stated twice drifts.
- Number every subsection and every deploy step under the section's own number
  - `1.4`, then `1.4.1`, `1.4.2` - so a step can be named in a chat or a call
  and pointed at from another subsection. Start each numbered subsection's
  heading with its number: that is what puts it in the page's contents rail.
- Mark anything the records did not settle and the diff did not answer as an
  **open question for the release owner**, never as a guess.
  An open question asks about the code or the system - how a repo ships, what a
  value should be - never whether a deploy step has been done.
