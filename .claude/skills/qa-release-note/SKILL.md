---
name: qa-release-note
description: Use when writing or reviewing a release note or deployment runbook for QA - turning a list of pull requests into plain-language statements of what should be true after the release, grouped by feature, with was/now for deliberate changes and the untested ones marked. Also read by /release-notes, which uses the per-repo facts this skill learns - who each path faces, where the app routes links, how config is read, what deploys on merge.
metadata:
  origin: workspace
  learns: true
  learns-reference: true
  fingerprint:
    - files deploy*.yml
    - files deploy*.yaml
---

# QA Release Note

This file is the method: how to turn pull requests into a release note a QA
team can test from, in any project. Which paths in a repo face which audience,
where its app routes links, how it reads configuration, what deploys when it
merges - those are facts about one repo, so they live in its learned file.

## Load the repo's facts first

For each repo in the release, start with its `AGENTS.md` if it has one, then:

```
.claude/scripts/learn.sh status qa-release-note
```

| State | Do |
|---|---|
| `fresh` | Read `.claude/learned/<repo>/qa-release-note.md` and follow it |
| `stale` | What it watches has moved. Run `/learn qa-release-note <repo>` before relying on it |
| `missing`, `unstamped` | Run `/learn qa-release-note <repo>` first, or say in the runbook that the repo's surfaces and deploy path were not learned |

`/release-notes` reads the same file for its `surface` and `deeplink` records, so a
repo with no learned file gets neither - its absence is reported, never guessed.
Where `AGENTS.md` and the learned file disagree, `AGENTS.md` wins.

## Where release facts come from

- **Every release fact comes from `gh`**: state, size, checks, diff, file list.
  A local checkout is only as fresh as its last fetch, and a stale one reports a
  repo as having nothing to release, or a 22-file change against a real 51.
- **Architecture comes from a git ref, never a working tree** - deploy
  triggers, contract copies, a route registry. A working tree may be a task's
  branch with unmerged work; it describes that task, not the service.
- **A release is the list of pull requests the user names.** Nothing infers it.
  Waves routinely merge a feature branch and a handful of hotfix branches into
  the same base on the same day.

## The test names are the QA section

The team already writes the QA section, inside test names - it just never
leaves the repo. `/release-notes` carries every added and removed assertion out
as a `test` record. Turn them into the release note in four moves:

- **Filter** the unit-internal ones. If a QA reader could not observe it -
  an error-mapping helper, a code generator, `TestMain`, plumbing that only
  propagates errors - drop it. Expect to drop around one in seven.
- **Pair** each removed assertion with the added one that replaced it. That
  pair *is* the behaviour change, and it gives you `was:` and `now:` for free:
  `publishes for every participant` -> `publishes for the organiser only`.
- **Translate** into product words. Never leave an identifier from the code in
  the release note.
- **Add the unchanged guards** - the lines tests cannot supply. When a change
  deliberately stops short of a neighbouring feature, say what stays true there.

## Judging the records

The facts script over-reports on purpose. These calls are yours:

- **`env` - read the file path, not just the key.** A key read where the repo
  reads service configuration (the learned file says where) belongs in the
  deployment config. A key read by a one-off tool, a backfill or a script run by
  hand **must not** go into the deployment config, even though it is new.
- **`gap` - keep only user-visible behaviour.** The heuristic is per directory,
  so it flags interfaces, DTOs and registries that are covered from elsewhere.
  Keep a gap only when the file changes something someone could notice, and
  mark it `⚠ NO TEST COVERS THIS - verify by hand`.
- **`deeplink` - the host is what the app routes on, the scheme means nothing**
  (it is usually configurable per environment). `NOT-IN-THE-APPS-REGISTRY` has
  three readings: another app's link, a test sentinel, or a link our own code
  emits that nothing will open. Only the third is a finding, and the app's
  checkout may be older than the app, so say it may have added the route since.
- **`surface` - who a changed file faces.** It comes only from the learned file;
  a repo with none learned gets none, and the audience must be read off the
  handler instead.
- **`proto` - a contract copied into other repos** changes a release task in
  every one of them, whether or not they are in the list.

## Writing the release note

Self-contained. **No reference points outside it** - no section numbers, no
watch-item ids, no PR numbers. It gets pasted into chat, where those dangle.

```
────────────────────────────────────────────────
1. ORDER DISCOUNT — who gets it          ⚠ CHANGED
────────────────────────────────────────────────
was:  every participant on a group order got the discount
now:  only the person who placed the order

- a member who PLACED the order, order completes
  → the discount is applied
- a member who was only ADDED to someone else's order
  → no discount
- the order was placed at the counter, no account → no discount

  Single-person orders are deliberately NOT changing:
- a member ordering alone STILL gets the discount
```

- **No screens, no navigation, no steps.** QA knows the app. They need to know
  what should be true, not where to click. Do not name a screen the diff cannot
  prove exists.
- **Group by feature, never by repo.** QA does not know which service moved.
- `was:` / `now:` only on deliberate changes. A bare line is something that
  should already be true and must stay true.
- **One noun per actor, used consistently.** A change with several easily
  confused actors - the person who ordered, the person added, the person
  rewarded - fixes one word for each and never varies it. This is the likeliest
  way the section misleads.
- Use a before/after table where the diff hands you one directly - old and new
  expected values in one test case are a table already.
- Mark an untested behaviour change `⚠ NO TEST COVERS THIS — verify by hand`.
- Close with **not in this release** (work on the branch that already shipped)
  and **not reachable by QA** (RPC, jobs, queue consumers, one-off scripts).

Scale check: one wave of about 110 assertions came to 12 sections.

## Two runbook sections that are easy to lose

- **Rollback residue** - durable side effects that survive a code rollback:
  codes already handed out, notification rows already written, backfilled data.
  Say explicitly what must *not* be cleaned up.
- **The previous release note.** Read it, carry forward its unresolved watch
  items, and flag reversals. Guidance to another team reversed four days later
  is caught by nothing else.
