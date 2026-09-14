# Discovering how a repo logs

Read by `/learn logging <repo>`. It lists what to find out about a repo's
logging and the exact shape to write it down in. Answer every heading with
measured facts. If a heading does not apply, write "none found" and name what
you searched, so a reader can tell absence from not looking.

## How to search: misses earlier scans made

- **Find the logger by its call sites, not its name.** Count calls per import,
  including an aliased import of a shared or internal module. A company-common
  package's `sw.LoggerErrorf` is the logger, and a grep for `logger\.` misses
  every call to it. One scan concluded "no structured logger" that way.
- **Dependencies are not usage.** A manifest can list two logging libraries, or
  one only transitively. Find what is actually called, and from where.
- **Read the logger's source,** in the repo or, for a shared Go module, in the
  module cache (`go env GOMODCACHE`). Its behaviour decides the rules: what it
  does before initialisation, which fields it writes, whether redaction really
  masks anything.
- **Two loggers: find which one reaches the log backend.** Follow the
  transports and exporters. The one with more call sites may print only to the
  console.
- **Quote globs in `grep --include='*.go'`.** zsh expands an unquoted one and the
  count silently comes back zero.

## What to find

1. **Logger.** What to call and how to import it. Its signature, and one real
   call from the repo. What else is in use that new code should not copy, with counts.
2. **Output and shipping.** Format (JSON or text), the fields each line carries,
   where it goes (stdout, file, OTel), and what reads it (Loki, SigNoz, CloudWatch).
3. **Request ID.** Where it is minted, how it travels (context, request object,
   child logger), and how to get it in a handler. Where it is lost: jobs,
   consumers, `context.Background()`, with counts.
4. **Message convention.** The dominant shape of a message or event name,
   measured, with examples.
5. **Errors.** Whether a central error handler exists, and whether unexpected
   errors reach the log backend or only the client, Discord, or a pager.
6. **Tests.** How tests silence or stub the logger, and what happens if they do not.
7. **Traps.** Existing habits new code must not copy: secrets or bodies logged,
   redaction that masks nothing, banners, emoji.

## Shape to write

```markdown
---
skill: logging
repo: <repo>
learned: pending
fingerprint: pending
reviewed: no
watch:
  - lines <file> <regex>
  - files <name-glob>
---

# <repo>: logging

## Logger
## Output and shipping
## Request ID
## Message convention
## Errors
## Tests
## Traps
```

- `learned` and `fingerprint` stay `pending`; `learn.sh stamp` fills them.
- `watch` holds what these facts rest on: the manifest line naming the logger or
  shared module, the wrapper file, and the lines mounting logging or request-ID
  middleware. Keep it narrow. A whole `go.mod` goes stale on every dependency
  bump, and a status that is always stale gets ignored.
- **Keep it under about 80 lines.** It is read on every load, so a reference
  manual defeats the point. Rules that hold in any repo belong in `SKILL.md`,
  not here.
