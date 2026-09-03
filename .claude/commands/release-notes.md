---
description: Turn a stated list of pull requests into a deployment runbook with a QA-readable release note
argument-hint: "<name>, then the PR URLs one per line"
allowed-tools: Bash(.claude/scripts/release-notes.sh:*), Read, Write, Glob, Grep
---

## Arguments

```
/release-notes hotfix-m51

https://github.com/Getswing-Team/sport-service/pull/1053
https://github.com/Getswing-Team/player-service/pull/599
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

A release here is **whatever pull requests the user names**. Nothing infers it,
and nothing should try. `sport`, `payment`, `player`, `backend` and `admin` all
merged `feature/m5.1` into `main` on 2026-09-02, but the same wave also merged
`hot/…` and `5.1-additional/…` straight to `main`, and `mobile` uses a scheme of
its own. There is no identifier a script could resolve.

The output is one file, `release/<date>-<name>.md`: a deployment runbook whose
headline section is a **release note** — plain-language behavioural assertions
the user pastes to their QA team.

`release/2026-09-02-5.1.md` is the reference implementation. Read it before
writing a new one.

## Two rules that are not matters of judgment

**Never read `repos/` for a release fact.** Those checkouts cannot be refreshed
from a session — `guard.sh` blocks `git fetch` under `repos/` — so they are only
as fresh as their last fetch. On 2026-09-03 `sport`'s local `main` was four
merged PRs behind. Reading them once reported `payment` as having nothing to
release and `player` as a 22-file change against a real 51. Every release fact
comes from `gh`. `repos/` is for slow-moving architecture only, and the script
has already read what it needs from there.

**Never read `spaces/` at all.** When you do need architecture the script did
not print — how a package is wired, what a handler already did — read it under
`repos/<repo>/`, never under `spaces/<task>/<repo>/`. A space is a worktree on
somebody's task branch carrying half-finished and uncommitted work, so it
describes that task rather than the service. That a space happens to be newer
than `repos/` is not a reason to prefer it: a release is described by what is on
the pull requests, and `gh` already gave you that.

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

It prints one `pr` line per URL and, under `missed`, other open PRs into the
same base that the user did **not** name.

Those `missed` lines matter. The top blocker of the 2026-09-02 release was four
PRs carrying content already inside the release PRs, with squash merge enabled —
merging any of them lands the same content under a new SHA. Every one was merged
anyway. **Surface the missed list to the user before the expensive read**, in one
short paragraph. Do not stop for approval; they may ignore it.

If the roll call reports no URLs, ask for them and stop.

### 2. Gather

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
| `proto` | a changed proto, and which other repos carry a copy |
| `deeplink` | a link an added line emits, checked against the app's route registry |
| `surface` | who a changed file faces, or which channel it arrives on |
| `test` | an added or removed test assertion — the extraction engine |
| `gap` | a changed source file with no test touched in the same directory |

For anything the records do not settle — why a change was made, what it means
for a player — read the PR diff. One reader per repo is reasonable for a large
release; keep synthesis in this session.

### 3. Judge the records

The script over-reports on purpose. Four calls are yours:

**`env` — read the file path, not just the key.** A key read in
`internal/infrastructure/config/config.go` is service configuration and belongs
in the deployment config. A key read in `cmd/<tool>/main.go` is a one-off run
by hand and **must not** go into the deployment config. Player's credit backfill
reads `BACKEND_DB_DSN` and `SPORT_DB_DSN`; both are wrong to deploy.

**`gap` — filter to user-visible behaviour.** The heuristic is per-directory, so
it flags interface files, DTOs and registries that are covered from elsewhere.
Keep a gap only when the file changes behaviour someone could notice. Two real
ones from `sport` #1040: the cashback narrowing in `order/create.go` and the
admin `booking_statuses` filter. Both are worth a line; a changed DTO is not.

**`deeplink` — the scheme is configurable and means nothing.** The host is what
the app routes on. `NOT-IN-THE-APPS-REGISTRY` has three readings: another app's
link (`dana://pay`), a test sentinel, or **a link our own code emits that
nothing will open**. Only the third is a finding. Note that `repos/mobile` is a
reference checkout and stale, so say the app may have added the route since.

**`test` — filter, translate, pair.** See below.

### 4. The extraction engine

The team already writes the QA section inside test names; it just never leaves
the repo. `test` records carry it out.

- **Filter** the unit-internal ones. From the 5.1 wave: `TestIsUniqueViolation`
  and its cases ("postgres duplicate key text", "sqlstate code alone"),
  `TestMain`, `TestNextReferralCode`, error-plumbing (`…PropagatesLookupErrors`).
  Roughly 15 of ~110. If a QA reader could not observe it, drop it.
- **Pair** each `-` record with the `+` that replaced it. That pair *is* the
  behaviour change, and it gives you `was:` / `now:` for free:
  `publishes for every player` → `publishes for owner only`.
- **Translate** into product words. "owner" → "the person who made the booking".
  Never leave a Go identifier in the release note.
- **Add the unchanged guards** — the lines tests cannot supply. `sport` and
  `backend` now use deliberately different referral rules, so *golf tee-times
  still reward an added player's referrer* belongs beside the change.

### 5. Write `release/<date>-<name>.md`

Sections, following the reference runbook:

1. At a glance — PR table, blockers, themes, blast radius
2. **Release note** — §6 below
3. What changed, per repo
4. Cross-service contracts
5. Deploy order, with the `deploy` records as a "merging is deploying" table
6. Data work — migrations, and any manual step such as a backfill
7. External configuration — env keys, third parties, mobile, admin
8. Rollback, **including durable residue**
9. Risks and watch items
10. Pre-deploy checklist and sign-offs
11. Post-deploy verification
12. Open questions for the release owner

Two of those are required rather than optional, because both were the strongest
part of the reference runbook and both are easy to lose on a blank page:

- **Rollback residue** — durable side effects that survive a code rollback:
  referral codes already handed out, notification rows already written,
  backfilled data. Say explicitly what must *not* be cleaned up.
- **Diff against the previous release note.** The roll call prints `prev`. Read
  it, carry forward its unresolved watch items, and flag reversals. The 09-02
  runbook reversed the 08-31 one's guidance to finance about referral volume
  four days later; nothing but this check catches that.

### 6. The release note section

Self-contained. **No reference points outside it** — no `§4`, no `W7`, no PR
numbers. It gets pasted into Slack, where those dangle.

```
────────────────────────────────────────────────
1. REFERRAL REWARD — who converts       ⚠ CHANGED
────────────────────────────────────────────────
was:  every player on a finished multisport order rewarded their referrer
now:  only the player who made the booking

- a referred player who MADE the booking, booking finishes
  → their referrer is rewarded
- a referred player who was only ADDED to someone else's order
  → their referrer is NOT rewarded
- the booker has no account (POS walk-in) → nobody is rewarded

  Golf tee-times are deliberately NOT changing:
- a player added to someone else's tee-time STILL rewards their referrer
```

Rules:

- **No screens, no navigation, no steps.** QA knows the app. They need to know
  what should be true, not where to click. Do not name a screen the diff cannot
  prove exists.
- **Group by feature, never by repo.** QA does not know which service moved.
- `was:` / `now:` only on deliberate changes. A bare line is something that
  should already be true and must stay true.
- **One noun per actor, used consistently.** The referral change has four
  easily-confused actors — referred player, referrer, order owner, invitee. Fix
  one word for each and never vary it. This is the likeliest way the section
  misleads.
- Use a before/after table where the diff hands you one directly — the receipt
  wording table came straight out of the old and new expected values in a single
  test case.
- Mark an untested behaviour change `⚠ NO TEST COVERS THIS — verify by hand`.
- Close with **not in this release** (work carried on the branch that already
  shipped) and **not reachable by QA** (gRPC, jobs, one-off scripts).

Scale check: the 5.1 wave produced 12 sections from ~110 assertions.

## What to refuse

- **Do not infer the PR list.** If the user names a milestone instead of URLs,
  ask for the URLs. There is no branch that identifies a release here.
- **Do not read `repos/` for release facts**, and do not report a divergence,
  file count or commit from a local checkout.
- **Do not read `spaces/` for anything.** Architecture comes from `repos/`; a
  space is one unfinished task, not the service.
- **Do not merge, push, deploy, or trigger a workflow**, and do not offer to.
- **Do not invent a test assertion.** If a behaviour has no `test` record, mark
  it as untested — never write a plausible-sounding line as though extracted.
- If `gh` fails on a PR, say which one and stop. Do not retry with a different
  repo, a guessed number, or the local checkout.
