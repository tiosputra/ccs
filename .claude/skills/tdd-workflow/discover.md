# Discovering how a repo tests

Read by `/learn tdd-workflow <repo>`. It lists what to find out about a repo's
tests and the exact shape to write it down in. Answer every heading with
measured facts. If a heading does not apply, write "none found" and name what
you searched, so a reader can tell absence from not looking.

## How to search: misses earlier scans made

- **The language comes from `go.mod` first.** A Go service can carry a
  `package.json` that only builds email templates or runs scripts. One scan
  nearly resolved such a repo to jest.
- **Run the commands, do not only read them.** A `test` script can point at a
  config that typechecks every file per worker and takes ten times longer than
  a transpile-only run. Time the full suite once, cold, and write the number down.
- **Read `testMatch`, `roots` and `setupFiles*` in the runner config,** not the
  directory names. A repo can accept both `__tests__/` and sibling `*.test.ts`.
- **Check whether `tsconfig.json` covers the test files.** If it does, `tsc
  --noEmit` typechecks them and a transpile-only test run loses nothing.
- **Check what the coverage reporter writes and whether it is gitignored.** A
  file reporter in a repo that does not ignore `coverage/` leaves a directory
  for the pull request to stage.
- **Twin paths are found by grepping one real field,** not by reading the
  architecture. Pick a field a recent commit added and list every file that
  produces it.

## What to find

1. **Runner.** Language, runner and version, the config file, and whether it
   typechecks during tests (ts-jest default) or transpiles.
2. **Commands.** The five placeholders the skill uses, as they run here, with
   concurrency caps: `<test>`, `<test-one>`, `<test-changed>`, `<coverage>`,
   `<build>`. For a ts-jest repo, whether `<jest>` (the workspace's
   transpile-only config) works against the repo's `jest.config.js`.
3. **Test layout.** Where unit, integration and service-level tests live, with
   one real path of each.
4. **Isolation.** Global setup files, how external dependencies are faked
   (interfaces, `jest.mock`, a test database), and one real example.
5. **Twin paths.** Where this repo builds the same object twice: detail and
   list routes, HTTP and socket or event payloads, ORM projections, sandbox or
   mock modes, version forks. Paths, not descriptions.
6. **Traps.** What new tests must not copy or trip on: a linter the repo says
   not to run during a change, cached results, flaky suites with names, focused
   scripts that use the slow config, tests that need a live service.
7. **Measurements.** Full-suite time and worker memory, cold cache, with the
   caps used and the date. Optional, but it is what justifies a cap.

## Shape to write

```markdown
---
skill: tdd-workflow
repo: <repo>
learned: pending
fingerprint: pending
reviewed: no
watch:
  - lines <file> <regex>
  - files <name-glob>
---

# <repo>: tdd-workflow

## Runner
## Commands

| `<test>` | `<test-one>` | `<test-changed>` | `<coverage>` | `<build>` |
|---|---|---|---|---|

## Test layout
## Isolation
## Twin paths
## Traps
## Measurements
```

- `learned` and `fingerprint` stay `pending`; `learn.sh stamp` fills them.
- `watch` holds what these facts rest on: the runner config file, the manifest
  line naming the runner, the `test` script or makefile target, and
  `files AGENTS.md` where the repo has one. Keep it narrow; a whole
  `package.json` goes stale on every dependency bump.
- **Keep it under about 80 lines.** It is read on every load. Rules that hold in
  any repo belong in `SKILL.md`, not here.
