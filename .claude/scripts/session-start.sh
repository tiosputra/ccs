#!/usr/bin/env bash
#
# session-start.sh - the SessionStart hook: tell a new session which open tasks
# have a saved working log, so it knows /resume-session has something to load.
#
# Prints a few lines that Claude Code adds to the session's context, or nothing
# when no open task has saved a session. The facts come from `task.sh logs`; this
# only formats them, newest first, at most five.
#
# It informs and never blocks. Every failure - a missing script, a bad metadata
# file, a date that will not parse - ends in silence and exit 0, and settings.json
# wraps the call in `; exit 0` as well, so a broken hook costs a session one
# missing hint, never a refused start. See ccs-conventions, "No hook enforces
# the rules", for why that matters here.
#
# Usage:
#   session-start.sh            what the hook runs; reads nothing from stdin

# No `set -e`: a report that aborts on the first failed grep reports nothing.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 0

# Days between YYYY-MM-DD and today; empty when the date does not parse.
days_ago() {
  local then now
  then="$(date -j -f '%Y-%m-%d' "$1" '+%s' 2>/dev/null || date -d "$1" '+%s' 2>/dev/null)" || return 0
  now="$(date '+%s')"
  printf '%s\n' $(( (now - then) / 86400 ))
}

rows="$("$SCRIPT_DIR/task.sh" logs 2>/dev/null | awk -F'\t' '$1 == "log" && $5 == "open"' | sort -t "$(printf '\t')" -k4,4r | head -n 5)"
[ -n "$rows" ] || exit 0

printf 'Open tasks with a saved session - `/resume-session <task>` briefs from its log:\n'
printf '%s\n' "$rows" | while IFS="$(printf '\t')" read -r _ task path saved _; do
  age="$(days_ago "$saved")"
  case "$age" in
    "")  when="$saved" ;;
    0)   when="$saved, today" ;;
    1)   when="$saved, 1 day ago" ;;
    *)   when="$saved, $age days ago" ;;
  esac
  printf -- '- %s - last saved %s - %s\n' "$task" "$when" "$path"
done
exit 0
