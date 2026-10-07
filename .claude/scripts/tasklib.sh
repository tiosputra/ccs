#!/usr/bin/env bash
#
# tasklib.sh - where a task's work lives. Sourced, never run.
#
# A task works in one of two layouts, chosen when it starts and fixed after:
#
#   inplace   repos/<repo>, on the task branch          (the default)
#   space     spaces/<task>/<repo>, a worktree per repo (opt in with --space)
#
# Everything that needs to find a task's files asks here instead of building a
# path, so the layout is decided in one place. task.sh writes the metadata;
# graph.sh, ccs.sh and task.sh read it through these functions.
#
# Metadata is one TSV file per task, gitignored:
#
#   .claude/state/tasks/<task>
#     task<TAB><task>
#     isolation<TAB>inplace|space
#     branch<TAB><branch>
#     created<TAB><utc timestamp>
#     base<TAB><repo><TAB><ref><TAB><sha>      one line per repo
#
# A space made before this file existed kept its metadata at
# spaces/<task>/.space in the same format, minus the isolation line. It is read
# as a space task, so open spaces survive the upgrade.
#
# Usage from a script:
#
#   . "$SCRIPT_DIR/tasklib.sh"
#   for t in $(task_names); do ...; done
#   cd "$(task_workdir fix-promo api)"

TL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TL_REPOS="$TL_ROOT/repos"
TL_SPACES="$TL_ROOT/spaces"
TL_STATE="$TL_ROOT/.claude/state/tasks"

# task_meta <task> - the task's metadata file, current or legacy. Fails if none.
task_meta() {
  if [ -f "$TL_STATE/$1" ]; then
    printf '%s\n' "$TL_STATE/$1"
  elif [ -f "$TL_SPACES/$1/.space" ]; then
    printf '%s\n' "$TL_SPACES/$1/.space"
  else
    return 1
  fi
}

# task_exists <task> - metadata, or a legacy space directory that predates it.
task_exists() {
  task_meta "$1" >/dev/null 2>&1 || [ -d "$TL_SPACES/$1" ]
}

# task_field <task> <key> - one top-level value. Empty if unset.
task_field() {
  local meta
  meta="$(task_meta "$1" 2>/dev/null)" || return 0
  awk -F'\t' -v k="$2" '$1==k {print $2; exit}' "$meta"
}

# task_isolation <task> - inplace or space. Legacy metadata has no line: space.
task_isolation() {
  local v
  v="$(task_field "$1" isolation)"
  printf '%s\n' "${v:-space}"
}

task_branch() { task_field "$1" branch; }

# task_repos <task> - the repos in the task, one per line, in the order added.
# A legacy space may have worktrees its metadata never recorded; those count.
task_repos() {
  local meta d
  {
    meta="$(task_meta "$1" 2>/dev/null)" && awk -F'\t' '$1=="base" {print $2}' "$meta"
    if [ "$(task_isolation "$1")" = space ]; then
      for d in "$TL_SPACES/$1"/*/; do
        [ -e "$d/.git" ] && basename "$d"
      done
    fi
  } | awk 'NF && !seen[$0]++'
}

# task_has_repo <task> <repo>
task_has_repo() {
  task_repos "$1" | grep -qx -- "$2"
}

# task_workdir <task> <repo> - absolute path of the repo's working directory for
# this task. Prints it whether or not it exists yet.
task_workdir() {
  case "$(task_isolation "$1")" in
    inplace) printf '%s\n' "$TL_REPOS/$2" ;;
    *)       printf '%s\n' "$TL_SPACES/$1/$2" ;;
  esac
}

# task_base <task> <repo> - "<ref><TAB><sha>" recorded when the repo joined.
task_base() {
  local meta
  meta="$(task_meta "$1" 2>/dev/null)" || return 1
  awk -F'\t' -v r="$2" '$1=="base" && $2==r {print $3 "\t" $4; found=1; exit} END {exit !found}' "$meta"
}

# task_names - every task this machine has open, one per line.
task_names() {
  local f d
  {
    for f in "$TL_STATE"/*; do
      [ -f "$f" ] && basename "$f"
    done
    for d in "$TL_SPACES"/*/; do
      [ -d "$d" ] && basename "$d"
    done
  } | sort -u
}

# task_holding <repo> - the in-place task whose branch repos/<repo> is on, if any.
task_holding() {
  local t
  for t in $(task_names); do
    [ "$(task_isolation "$t")" = inplace ] || continue
    task_has_repo "$t" "$1" && { printf '%s\n' "$t"; return 0; }
  done
  return 1
}

# task_log <task> - docs/<date>_<task>/log.md, absolute, if the task has one. The
# date is the day the task opened and cannot be derived, so it is globbed.
task_log() {
  local d
  for d in "$TL_ROOT"/docs/*_"$1"/; do
    [ -f "${d}log.md" ] && { printf '%s
' "${d}log.md"; return 0; }
  done
  return 1
}

# log_closed <log.md> - true once /task finish has written a dated Closed. An open
# task's working log, kept by /save-session, carries `Closed: -` instead.
log_closed() {
  grep -Eq 'Closed[:*]* *[0-9]{4}-[0-9]{2}-[0-9]{2}' "$1"
}

# log_last_saved <log.md> - date of the newest `### YYYY-MM-DD` session entry, or
# the file's modification date when it has none (a log written before sessions).
log_last_saved() {
  local last
  last="$(grep -oE '^### [0-9]{4}-[0-9]{2}-[0-9]{2}' "$1" 2>/dev/null | sed 's/^### //' | sort | tail -n 1 || true)"
  [ -n "$last" ] || last="$(date -r "$1" '+%Y-%m-%d' 2>/dev/null || true)"
  printf '%s\n' "${last:--}"
}
