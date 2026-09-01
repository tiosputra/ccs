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
#   1. the environment    SPACE_BRANCH_PREFIX=x space.sh add …   (one-off)
#   2. .env               your standing preference
#   3. the built-in       what someone with no .env gets
#
# Usage from a script:
#
#   . "$SCRIPT_DIR/config.sh"
#   cfg_resolve SPACE_BRANCH_PREFIX ccs
#   echo "$SPACE_BRANCH_PREFIX came from $(cfg_source SPACE_BRANCH_PREFIX)"

CFG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CFG_FILE="$CFG_ROOT/.env"
CFG_SOURCES=""

# One key's value from .env, unquoted and trimmed. Last assignment wins.
cfg_file_value() {
  [ -f "$CFG_FILE" ] || return 0
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$CFG_FILE" \
    | grep -v '^#' | tail -1 \
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

cfg_source() {
  printf '%s' "$CFG_SOURCES" | awk -F'\t' -v n="$1" '$1==n {s=$2} END {print (s?s:"unset")}'
}

cfg_file() { printf '%s' "$CFG_FILE"; }
