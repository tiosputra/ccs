# docs/

Everything written about a task, in one directory per task:

```
docs/<YYYY-MM-DD>_<task>/
├── prd.md        the requirements, written by /plan-prd and confirmed at Gate 1
├── plan.md       the implementation plan for milestone 1, written by /plan
├── plan-m2.md    one more file per later milestone: plan-m2.md, plan-m3.md, ...
├── api-contract.md  what consumers see change, read by frontend and mobile
├── testing.md    the RED/GREEN evidence, one section per repo the task touched
├── log.md        the wrap-up note, written from `space.sh report` before teardown
└── <anything>    supporting files: a backfill .sql, a .csv export, request examples
```

The named files are the standard artifacts, and commands find them by exact name.
Anything else the task produces sits beside them, named for what it is. The one
thing not to write is a renamed copy of a standard artifact — `plan-v2.md`,
`testing-backend.md` — which no command will ever read.

The date is the day the task **opened** — the day its PRD was written — and never
changes afterwards. The task name is the same kebab-case word used for the space,
the branch, and every artifact: `spaces/<task>/`, `<prefix>/<task>`.

Because the date is not derivable from the task name, find a task's directory by
globbing rather than guessing:

```bash
ls -d docs/*_<task>/
```

Not every file is always present. A task abandoned after Gate 1 has only a
`prd.md`; a task that ran outside the flow may have only a `log.md`.

The contents stay local — they describe private services and their production
incidents — so this README is the only tracked file here.
