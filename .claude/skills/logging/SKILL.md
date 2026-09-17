---
name: logging
description: Use when writing or changing service code that can fail, talks to something outside the process, or changes state - a handler, usecase, repository call, job, queue consumer, webhook callback, or external API call - so it logs through the repo's existing logger, carries the request ID, picks the right level, and leaks no secrets. Also use when reviewing code for missing or noisy logs.
metadata:
  origin: swing
  learns: true
  fingerprint:
    - lines go.mod (go.uber.org/zap|rs/zerolog|sirupsen/logrus|lumberjack|apex/log|go-kit/log)
    - lines package.json (winston|pino|bunyan|log4js|consola|loglevel|signale)
---

# Logging

This file is the method: how to log well in any codebase. Which logger *this*
repo uses, how its request ID travels, and which of its habits not to copy are
facts about one repo, so they live in its learned file, not here.

## Load the repo's facts first

The repo is the checkout being changed: `spaces/<task>/<repo>/` means `<repo>`.
A project with no `repos/` is one repo, named after its directory.

Start with the repo's own `AGENTS.md`, if it has one — the team's rules, committed
beside the code. Then the learned file:

```
.claude/scripts/learn.sh status logging
```

| State | Do |
|---|---|
| `fresh` | Read `.claude/learned/<repo>/logging.md` and follow it |
| `stale` | The code it watches has moved. Run `/learn logging <repo>` before relying on it |
| `missing`, `unstamped` | Run `/learn logging <repo>` first |

If the row says `unreviewed`, follow the file but say in your report that no
one has checked it yet.

Three layers, highest first, each winning only where it actually speaks:

| Layer | Why it ranks there |
|---|---|
| `<repo>/AGENTS.md` | The team's own rules for that codebase, committed with it |
| `.claude/learned/<repo>/logging.md` | Measured in that repo, but on one machine and by a scan |
| this skill | The method, true anywhere, measured nowhere |

So where `AGENTS.md` and the learned file disagree about the logger, the level,
or what never to log, follow `AGENTS.md` and say so in your report — the learned
file is a scan of the code, and the repo's rule may be what the code is moving
towards. Where `AGENTS.md` is silent, the learned file wins over this skill,
because it was measured there. Where both are silent, this skill applies.

## Use the logger the repo already has

- **Never add a logging library, and never wrap the existing one inside a
  task.** Replacing the logger is its own task.
- **When a repo has two loggers, use the one wired to where logs are read.**
  The one with more call sites may be the one nobody can search.
- **Stdlib prints are leftovers, not a pattern.** `fmt.Println`, `log.Printf`
  and `console.log` carry no level and no request ID, and they rarely reach the
  log backend.

## Carry the request ID

- **Pass the request-scoped context or logger down every layer.** A fresh
  `context.Background()`, or a module-level logger, drops the ID, and the line
  can no longer be tied to its request.
- **Work that does not start from a request gets its own ID** at the start of
  each unit of work: one job run, one queue message, one webhook, one script.
- **If middleware already logs every request** (method, path, status, latency),
  do not log "request received" from a handler.

## Levels

| Level | When | Example |
|---|---|---|
| `error` | The operation failed and someone may need to act | payment rejected, DB write failed, message dropped |
| `warn` | Degraded, but handled | retrying, falling back to a default, skipping a duplicate |
| `info` | A business state changed, or a call left the process | order created, refund issued, provider returned `status=PAID` |

Use `debug` only if the repo's logger has it and production filters it out.
A line that only helped while writing the code gets deleted before review.

## What to log

- **State transitions** (created, paid, cancelled, refunded, expired), with the IDs.
- **Calls out of the process** (payment providers, other services, gRPC,
  queues): what was called, the outcome, the status code, and the external
  reference ID.
- **Decisions a later reader must reconstruct:** why a request was rejected,
  why a retry was skipped.
- **A job or consumer run:** its scope at the start, and a count at the end
  (`processed=12 failed=1`).

## What never to log

- **Secrets:** API keys (not even a prefix), tokens, `Authorization` headers,
  passwords, PINs, card data, webhook signatures.
- **Whole request or response bodies,** above all from payment providers. Pick
  the fields you need.
- **Personal data beyond an ID:** emails, phone numbers, names, addresses. Log
  the user's ID, not the user.
- **One line per item** in a loop over a collection. Log the summary.

**Do not trust redaction to catch it.** A masking helper is only as good as
its list, and lists go stale. Choose the fields yourself.

## Log once, at the call that failed

A failure gets exactly one application log line. Two layers logging the same
error make one failure look like three - but a single line at the boundary has
the opposite problem: it says the request failed without saying *which call*
failed, so a malformed identifier and an unreachable dependency read alike.

So the line goes **where the call is made**, immediately before the error is
returned:

- **The layer that performs the operation logs it,** because only it knows what
  was being attempted. A caller that receives an error returns it without
  logging again.
- **Name the operation, not the request.** "delete tag links by device id" beats
  "update failed". A reader should be able to tell which of several calls in one
  function failed without opening the file.
- **Carry what the operation acted on** - the identifiers - and the underlying
  error.
- **Expected outcomes are not failures.** Validation rejections and not-found
  end as 4xx: they are the caller's mistake, not the service's, and middleware
  that writes an access line has already recorded them. Logging them at error
  level buries the real failures.

Know what the central error handler does. If it does not write unexpected errors
to the log backend, the call site is the only place they are recorded.

## Keep messages stable

Keep the message fixed, and put variables in fields. If the logger has no
fields, follow the repo's `key=value` convention inside the message. A stable
message is one you can count and alert on.

No emoji and no banners, even where the repo already has them.

## Tests

If the logger fails or panics before it is initialised, stub it the way the
repo's tests already do. Never initialise the real logger in a test, because
it may write files or ship logs.
