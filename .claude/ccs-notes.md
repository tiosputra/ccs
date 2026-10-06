# ccs notes

Friction found while running real tasks, recorded in the moment so it is still
true when someone reads it. One line each; `/ccs` turns them into a worklist.

Written by `.claude/scripts/ccs.sh note`. Tick a line off when it ships.

- [x] 2026-09-01 — guard.sh blocks read-only commands: any redirect (even 2>/dev/null) after 'cd repos/…' trips its cd rule; fixed by resolving each redirect target against the cd'd directory
- [x] 2026-09-01 — guard blocks 'git -C repos/X branch --list' — 'branch' is in its MUTATING list, but --list and --merged only read; fixed by splitting branch/tag/worktree/stash into read-only and mutating forms
- [x] 2026-09-01 — guard's redirect rule matches an ASCII arrow in prose: writing a heredoc containing a repos/ path preceded by the two-character arrow reads as a redirection into repos/; fixed, '->' and '=>' are no longer redirect operators
- [x] 2026-09-01 — repos/README.md is tracked in git (gitignore un-ignores it) but the guard blocks all writes under repos/, so it can never be edited from a session; fixed, the roster file is carved out while every repos/<repo>/… path stays sealed
- [x] 2026-09-01 — test runs spawn one node worker per core, multiplied by concurrent sessions; fixed by capping concurrency in tdd-workflow's Step 0 matrix ("Bounded runs")
- [x] 2026-09-25 — guard.sh resolves an unexpanded shell-variable redirect target (redirecting to SP/out.txt with SP set earlier in the same command) against the cd'd directory, so after cd into a repos checkout a scratchpad write is refused; it also reads a quoted redirect symbol inside a ccs note as a real redirect; worked around by spelling literal paths; moot, guard.sh removed 2026-09-30
- [x] 2026-09-28 — i just add a new agents can u check the flow in our sistem again; fixed, go-build-resolver adapted to run by hand, and /ccs now checks every agent is reached by a command or run by hand and never claims PROACTIVELY / MUST BE USED
- [x] 2026-09-29 — why this failed slashtask finish init-project: Shell command failed for pattern "!`.claude/scripts/task.sh slash finish init-project`": (eval):1: no such file or directory: .claude/scripts/task.sh; cause: a `cd` in an earlier Bash call moved the session's working directory, and every command's `!` line calls its script by a relative path; fixed, settings.json sets CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR=1 so the shell returns to the workspace root after each command
- [x] 2026-10-06 — i just add bunch of agents, commands, skills and some i committed already; fixed: ADR skill restored to its adapted version; architect, planner, code-reviewer and security-reviewer adapted and placed in the flow; council, dev-team, santa-method, search-first, team-builder, iterative-retrieval adapted; save/resume-session keep the task's log.md (closed now means a dated Closed); knowledge-ops runs on the memory MCP server via graph.sh; ECC's session library replaced by task.sh logs and one fail-open SessionStart hook; /ccs now checks JS under scripts/ and that every hook fails open
