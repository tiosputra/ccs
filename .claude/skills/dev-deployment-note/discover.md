# Discovering how a repo deploys

Read by `/learn dev-deployment-note <repo>`. It lists what to find out about how
a repo reaches production and how it comes back, and the exact shape to write it
down in. Answer every heading with measured facts. If a heading does not apply,
write "none found" and name what you searched, so a reader can tell absence from
not looking.

No section here is read by a script. `/deployment-notes` reads the whole file
for a developer, so write it for one.

## How to search: misses earlier scans made

- **Service config is usually read in one place; one-off tools read their own.**
  Find the file that loads the service's configuration, and separately any
  command, script or backfill that reads its own environment - those keys must
  never be deployed.
- **Where a value is set is not where it is read.** A key read from the
  environment is provisioned somewhere else - CI secrets, a manifest, a config
  service, a file on a server. Record where, or say it is not in the repo.
- **The deploy workflow is the one that runs on merge to the production
  branch**, which is not always the one named `deploy`. Read its `on:` block,
  and note any environment that merges deploy to before production.
- **Migrations may run on boot, as a pipeline step, or by hand.** Find which -
  it decides whether a deploy and its migration can be separated.
- **Read at the default branch** (`git show origin/HEAD:<path>`), not in the
  working tree, which may be a task's branch.

## What to find

1. **Config.** Where the service reads configuration, the form a key read takes
   in code, where values are provisioned per environment, and where one-off
   tools read theirs. What happens on boot when a required key is missing.
2. **Deploy.** The workflow per environment, its trigger, and what merging to
   each branch actually does. How it reaches traffic: replace, rolling, canary,
   blue-green, and any health check that gates it.
3. **Migrations.** The tool, where migration files live, how they run, and
   whether down migrations exist and are trusted.
4. **Rollback.** How a bad release is undone in practice: revert and merge,
   redeploy a previous tag or image, a manual trigger. How long it takes.
5. **Feature flags.** The mechanism, if any, and where a flag's state is set.
6. **Shared contracts.** Protos, schemas or clients this repo copies from, or
   into, another repo, with the paths.
7. **Observability.** Where logs, metrics, alerts and error tracking for this
   service are read after a deploy.

## Shape to write

```markdown
---
skill: dev-deployment-note
repo: <repo>
learned: pending
fingerprint: pending
reviewed: no
watch:
  - files <name-glob>
  - lines <file> <regex>
---

# <repo>: dev-deployment-note

## Config
## Deploy
## Migrations
## Rollback
## Feature flags
## Shared contracts
## Observability
```

- `learned` and `fingerprint` stay `pending`; `learn.sh stamp` fills them.
- `watch` holds what these facts rest on: the config loader, the deploy
  workflows, the migration runner's setup, container and manifest files, and
  `files AGENTS.md` where the repo has one.
- **Keep it under about 60 lines.** It is read on every release.
