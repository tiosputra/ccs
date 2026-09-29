# ccs notes

Friction found while running real tasks, recorded in the moment so it is still
true when someone reads it. One line each; `/ccs` turns them into a worklist.

Written by `.claude/scripts/ccs.sh note`. Tick a line off when it ships.

- [x] 2026-09-01 — guard.sh blocks read-only commands: any redirect (even 2>/dev/null) after 'cd repos/…' trips its cd rule; fixed by resolving each redirect target against the cd'd directory
- [x] 2026-09-01 — guard blocks 'git -C repos/X branch --list' — 'branch' is in its MUTATING list, but --list and --merged only read; fixed by splitting branch/tag/worktree/stash into read-only and mutating forms
- [x] 2026-09-01 — guard's redirect rule matches an ASCII arrow in prose: writing a heredoc containing a repos/ path preceded by the two-character arrow reads as a redirection into repos/; fixed, '->' and '=>' are no longer redirect operators
- [x] 2026-09-01 — repos/README.md is tracked in git (gitignore un-ignores it) but the guard blocks all writes under repos/, so it can never be edited from a session; fixed, the roster file is carved out while every repos/<repo>/… path stays sealed
- [x] 2026-09-01 — test runs spawn one node worker per core, multiplied by concurrent sessions; fixed by capping concurrency in tdd-workflow's Step 0 matrix ("Bounded runs")
- [ ] 2026-09-25 — guard.sh resolves an unexpanded shell-variable redirect target (redirecting to SP/out.txt with SP set earlier in the same command) against the cd'd directory, so after cd into a repos checkout a scratchpad write is refused; it also reads a quoted redirect symbol inside a ccs note as a real redirect; worked around by spelling literal paths
- [x] 2026-09-28 — i just add a new agents can u check the flow in our sistem again; fixed, go-build-resolver adapted to run by hand, and /ccs now checks every agent is reached by a command or run by hand and never claims PROACTIVELY / MUST BE USED
- [ ] 2026-09-29 — why this failed slashtask finish init-project: Shell command failed for pattern "!`.claude/scripts/task.sh slash finish init-project`": (eval):1: no such file or directory: .claude/scripts/task.sh
