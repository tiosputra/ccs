# spaces/

Worktrees for tasks started with `--space`: one directory per task, holding a
git worktree for every repo that task touches, all on the task's
`<prefix>/<task>` branch. `.claude/scripts/task.sh` creates and removes them.

A task started without `--space` works in place, in `repos/<repo>`, and has
nothing here. `task.sh where <task> <repo>` says where any task's work is.
