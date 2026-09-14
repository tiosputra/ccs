# learned/

What a skill has learned about one repo, written once so no session has to
rediscover it.

```
learned/<repo>/<skill>.md
```

A skill that learns is split in two. Its `SKILL.md` is the **method**: how to do
the thing well in any codebase, naming no repo and no library. The file here
holds the **facts** for one repo: which logger backend uses, how sport's
request ID travels, which habits not to copy. The skill reads this file when it
loads and follows it where the two disagree.

| Step | Who |
|---|---|
| Scan a repo and write the file in the shape the skill's `discover.md` gives | `/learn <skill> <repo>` |
| Stamp the date and a fingerprint of the code the file watches | `learn.sh stamp`, never by hand |
| Say which files are fresh, stale, unstamped, or missing | `learn.sh status`, `/learn` |
| Confirm the facts are right (`reviewed: yes`) | you |

A file goes **stale** when anything in its `watch:` list changes, such as the
logger dependency's version or the middleware that mounts it. Re-run
`/learn` then. The fingerprint does not cover `reviewed`, so confirming a file
does not make it stale.

## Why only this README is tracked

These files describe the private services: their loggers, their internals, the
places they leak data. This repo ships the workspace system, not the services,
so like `docs/` the contents stay on the machine that learned them. Each machine
runs `/learn` once per repo.

If a repo's facts should be shared with its whole team, the durable home is that
repo's own `AGENTS.md`, committed through a task, not a file here.
