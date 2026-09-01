# ccs notes

Friction found while running real tasks, recorded in the moment so it is still
true when someone reads it. One line each; `/ccs` turns them into a worklist.

Written by `.claude/scripts/ccs.sh note`. Tick a line off when it ships.

- [ ] 2026-09-01 — guard.sh blocks read-only commands: any redirect (even 2>/dev/null) after 'cd repos/…' trips its cd rule
- [ ] 2026-09-01 — guard blocks 'git -C repos/X branch --list' — 'branch' is in its MUTATING list, but --list and --merged only read. Use for-each-ref instead.
- [ ] 2026-09-01 — guard's redirect rule matches an ASCII arrow in prose: writing a heredoc containing a repos/ path preceded by the two-character arrow reads as a redirection into repos/.
- [ ] 2026-09-01 — repos/README.md is tracked in git (gitignore un-ignores it) but the guard blocks all writes under repos/, so it can never be edited from a session.
