#!/usr/bin/env bash
#
# config.sh - resolves per-machine workspace settings. Sourced, never run.
#
# The workspace system is shared; the settings are not. Branch prefix and
# default base ref differ per person, so they live in a gitignored `.env` at
# the workspace root rather than in any tracked file or doc.
#
#   .env            yours, gitignored, never committed
#   .env.example    the tracked template listing every setting
#
# Precedence, highest first:
#
#   1. the environment    TASK_BRANCH_PREFIX=x task.sh start …   (one-off)
#   2. .env               your standing preference
#   3. the built-in       what someone with no .env gets
#
# Usage from a script:
#
#   . "$SCRIPT_DIR/config.sh"
#   cfg_resolve REFERENCE_REPOS ""
#   cfg_resolve_renamed TASK_BRANCH_PREFIX SPACE_BRANCH_PREFIX ccs
#   echo "$TASK_BRANCH_PREFIX came from $(cfg_source TASK_BRANCH_PREFIX)"

CFG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CFG_FILE="$CFG_ROOT/.env"
CFG_SOURCES=""

# One key's value from .env, unquoted and trimmed. Last assignment wins.
# A key .env does not set is an empty value, not a failure: the callers run
# under `set -e -o pipefail`, where a grep that matches nothing ends the script.
cfg_file_value() {
  [ -f "$CFG_FILE" ] || return 0
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$CFG_FILE" \
    | { grep -v '^#' || true; } | tail -1 \
    | sed -e 's/[[:space:]]*#.*$//' -e 's/^"//' -e 's/"$//' \
          -e "s/^'//" -e "s/'\$//" -e 's/[[:space:]]*$//'
}

# cfg_resolve <NAME> <fallback> - sets $NAME and records where it came from.
cfg_resolve() {
  local name="$1" fallback="$2" cur val
  eval "cur=\${$name:-}"
  if [ -n "$cur" ]; then
    CFG_SOURCES="$CFG_SOURCES$name	environment
"
    return 0
  fi
  val="$(cfg_file_value "$name")"
  if [ -n "$val" ]; then
    eval "$name=\"\$val\""
    CFG_SOURCES="$CFG_SOURCES$name	.env
"
  else
    eval "$name=\"\$fallback\""
    CFG_SOURCES="$CFG_SOURCES$name	built-in default
"
  fi
}

# cfg_resolve_renamed <NAME> <OLD_NAME> <fallback> - as cfg_resolve, for a
# setting that was renamed. The new name wins at every layer; the old name is
# still honoured, from the environment or .env, before the built-in default.
# cfg_source then reports e.g. ".env (as OLD_NAME)" so /task config shows
# which spelling a machine still uses.
cfg_resolve_renamed() {
  local name="$1" old="$2" fallback="$3" cur val
  cfg_resolve "$name" ""
  eval "cur=\${$name:-}"
  [ -n "$cur" ] && return 0
  eval "val=\${$old:-}"
  if [ -n "$val" ]; then
    eval "$name=\"\$val\""
    CFG_SOURCES="$CFG_SOURCES$name	environment (as $old)
"
    return 0
  fi
  val="$(cfg_file_value "$old")"
  if [ -n "$val" ]; then
    eval "$name=\"\$val\""
    CFG_SOURCES="$CFG_SOURCES$name	.env (as $old)
"
  else
    eval "$name=\"\$fallback\""
    CFG_SOURCES="$CFG_SOURCES$name	built-in default
"
  fi
}

cfg_source() {
  printf '%s' "$CFG_SOURCES" | awk -F'\t' -v n="$1" '$1==n {s=$2} END {print (s?s:"unset")}'
}

cfg_file() { printf '%s' "$CFG_FILE"; }
