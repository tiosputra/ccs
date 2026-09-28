# Discovering how a repo releases

Read by `/learn qa-release-note <repo>`. It lists what to find out about a
repo's release surface and the exact shape to write it down in. Answer every
heading with measured facts. If a heading does not apply, write "none found"
and name what you searched, so a reader can tell absence from not looking.

Two sections are read by `.claude/scripts/release-notes.sh`, not only by a
model, so their lines follow a strict form: `## Surfaces` and
`## Deeplink registry`. Anything else in those sections is ignored by the
script.

## How to search: misses earlier scans made

- **Surfaces come from how routes are mounted, not from folder names alone.**
  Find where HTTP routes, RPC services, consumers and jobs are registered, then
  map the directories that hold them. A folder called `admin` that no admin
  route reaches is not the admin surface.
- **Some repos name their audience in the path, some only partly, some not at
  all.** Record only what the path really decides. Where the audience is read
  off the handler instead, say so and leave the path out.
- **Service config is usually read in one place; one-off tools read their own.**
  Find the file that loads the service's configuration, and separately any
  command, script or backfill that reads its own environment - those keys must
  never be deployed.
- **The deploy workflow is the one that runs on merge to the production branch**,
  which is not always the one named `deploy`. Read its `on:` block.
- **Read architecture at the default branch** (`git show origin/HEAD:<path>`),
  not in the working tree, which may be a task's branch.

## What to find

1. **Surfaces.** Path globs that decide who a changed file faces: an app, an
   admin panel, a public API, a partner API, service-to-service RPC, a queue
   consumer, a scheduled job, email, PDF, a realtime socket.
2. **Config.** Where the service reads its configuration, the form a key read
   takes in code, and where one-off tools read theirs.
3. **Deploy.** The workflow that ships production, its trigger, and what merging
   to the base branch actually does.
4. **Deeplink registry.** Only for an app that routes links: the file that lists
   the hosts it can open, and the literal form a host takes in it.
5. **Shared contracts.** Protos, schemas or clients this repo copies from, or
   into, another repo, with the paths.
6. **Tests.** The assertion forms that carry behaviour here - `t.Run("…")`,
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

## Config
## Deploy

## Deeplink registry
- file: `lib/routes/app_links.dart`
- host: `'{host}'`

## Shared contracts
## Tests
```

- `## Surfaces`: one line per glob, exactly `` - `<glob>` -> <audience> ``.
  The glob is matched against repo-relative paths, and `*` crosses `/`.
- `## Deeplink registry`: only in the app's own learned file. `file:` is the
  registry's repo-relative path; `host:` is how a routable host appears in it,
  with `{host}` where the host goes. Leave the section out for any other repo.
- `learned` and `fingerprint` stay `pending`; `learn.sh stamp` fills them.
- `watch` holds what these facts rest on: the route registration files, the
  config loader, the deploy workflow, the registry file, and `files AGENTS.md`
  where the repo has one.
- **Keep it under about 60 lines.** It is read on every release.
