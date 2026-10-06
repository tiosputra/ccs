# Discovering how a repo releases

Read by `/learn qa-release-note <repo>`. It lists what to find out about a
repo's release surface - who its changes reach, and how its tests carry
behaviour - and the exact shape to write it down in. How the repo is
configured and deployed is learned by `dev-deployment-note` instead. Answer every
heading with measured facts. If a heading does not apply, write "none found"
and name what you searched, so a reader can tell absence from not looking.

Two sections are read by `.claude/scripts/deployment-notes.sh`, not only by a
model, so their lines follow a strict form: `## Surfaces` and
`## Deeplink registry`. Anything else in those sections is ignored by the
script.

## How to search: misses earlier scans made

- **Surfaces come from how routes are mounted, not from folder names alone.**
  Find where HTTP routes, RPC services, consumers and jobs are registered, then
  map the directories that hold them. A folder called `internal` that a
  public route reaches is not internal.
- **Some repos name their audience in the path, some only partly, some not at
  all.** Record only what the path really decides. Where the audience is read
  off the handler instead, say so and leave the path out.
- **Read architecture at the default branch** (`git show origin/HEAD:<path>`),
  not in the working tree, which may be a task's branch.

## What to find

1. **Surfaces.** Path globs that decide who a changed file faces: an app, an
   admin panel, a public API, a partner API, service-to-service RPC, a queue
   consumer, a scheduled job, email, PDF, a realtime socket.
2. **Deeplink registry.** Only for an app that routes links: the file that lists
   the hosts it can open, and the literal form a host takes in it.
3. **Tests.** The assertion forms that carry behaviour here - `t.Run("…")`,
   `it("…")`, table cases - so a reader knows what the `test` records cover.

## Shape to write

```markdown
---
skill: qa-release-note
repo: <repo>
learned: pending
fingerprint: pending
reviewed: no
watch:
  - lines <file> <regex>
  - files <name-glob>
---

# <repo>: qa-release-note

## Surfaces
- `*/delivery/http/admin/*` -> admin panel
- `*/delivery/grpc/*` -> RPC - service to service, QA cannot reach directly

## Deeplink registry
- file: `lib/routes/app_links.dart`
- host: `'{host}'`

## Tests
```

- `## Surfaces`: one line per glob, exactly `` - `<glob>` -> <audience> ``.
  The glob is matched against repo-relative paths, and `*` crosses `/`.
- `## Deeplink registry`: only in the app's own learned file. `file:` is the
  registry's repo-relative path; `host:` is how a routable host appears in it,
  with `{host}` where the host goes. Leave the section out for any other repo.
- `learned` and `fingerprint` stay `pending`; `learn.sh stamp` fills them.
- `watch` holds what these facts rest on: the route registration files, the
  registry file, the test helpers that shape assertions, and `files AGENTS.md`
  where the repo has one.
- **Keep it under about 60 lines.** It is read on every release.
