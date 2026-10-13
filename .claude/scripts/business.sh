#!/usr/bin/env bash
#
# business.sh - what the business pipelines have written so far. Read-only.
#
# Tasks change code in repos. The business pipelines change nothing there:
# /idea, /brand, /market and /decide write documents into business/, and this
# script says what is already on disk, how old it is, and what has gone stale,
# so each command can choose the next step from facts instead of guesses.
#
# Usage:
#   business.sh idea <name>        one idea: valid name?, its directory, its files
#   business.sh ideas              every idea, with the verdict its brief records
#   business.sh brand              brand-discovery progress, the voice profile
#   business.sh market             what /market has written, and what is stale
#   business.sh decide             every input /decide reads, and what is newer
#   business.sh slash <cmd> [sub]  dispatcher for /idea, /brand, /market, /decide
#
# Output is key<TAB>value lines. Under `slash`, the first line is mode<TAB>...

# No `set -e`: this reports, and a grep that matches nothing is an answer.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# The layout, decided here once. Commands print these paths, never build them.
BIZ="$ROOT/business"
IDEAS="$BIZ/ideas"
BRAND="$BIZ/branding"
MARKET="$BIZ/marketing"
DECIDE="$BIZ/decide.md"
# brand-discovery's module sequence is its reference files; read, not restated.
BRAND_REFS="$ROOT/.claude/skills/brand-discovery/references"

usage() { sed -n '3,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

rel() { printf '%s\n' "${1#"$ROOT"/}"; }

# fdate <file> - the day it was last written, or `-`.
fdate() { if [ -e "$1" ]; then date -r "$1" +%Y-%m-%d; else printf -- '-\n'; fi; }

# file_row <key> <file> - key<TAB>path<TAB>present|missing<TAB>date
file_row() {
  if [ -e "$2" ]; then
    printf '%s\t%s\tpresent\t%s\n' "$1" "$(rel "$2")" "$(fdate "$2")"
  else
    printf '%s\t%s\tmissing\t-\n' "$1" "$(rel "$2")"
  fi
}

# verdict <brief.md> - go | no-go | not-yet | -, from its `**Verdict:**` line.
verdict() {
  local v
  [ -f "$1" ] || { printf -- '-\n'; return; }
  v="$(grep -m1 -E '\*\*Verdict:\*\*' "$1" 2>/dev/null | sed 's/.*\*\*Verdict:\*\*[[:space:]]*//' | tr 'A-Z' 'a-z')"
  case "$v" in
    no-go*|no\ go*) printf 'no-go\n' ;;
    not\ yet*|not-yet*) printf 'not-yet\n' ;;
    go*) printf 'go\n' ;;
    *) printf -- '-\n' ;;
  esac
}

valid_name() { printf '%s' "$1" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$'; }

# ------------------------------------------------------------------ ideas --

cmd_idea() {
  local name="${1:-}" d f
  [ -n "$name" ] || { printf 'error\tmissing <name>\n'; return 0; }
  printf 'name\t%s\n' "$name"
  if ! valid_name "$name"; then
    printf 'valid\tno\tan idea name is kebab-case: lowercase letters, digits and single hyphens\n'
    return 0
  fi
  printf 'valid\tyes\n'
  d="$IDEAS/$name"
  printf 'dir\t%s\n' "$(rel "$d")"
  if [ -d "$d" ]; then printf 'exists\tyes\n'; else printf 'exists\tno\n'; fi
  file_row brief "$d/brief.md"
  printf 'verdict\t%s\n' "$(verdict "$d/brief.md")"
  for f in "$d"/investor/*; do
    [ -f "$f" ] || continue
    printf 'investor\t%s\t%s\n' "$(rel "$f")" "$(fdate "$f")"
  done
}

cmd_ideas() {
  local d name n=0 inv
  for d in "$IDEAS"/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    inv=no; [ -d "$d/investor" ] && [ -n "$(ls -A "$d/investor" 2>/dev/null)" ] && inv=yes
    # idea<TAB><name><TAB><brief date | -><TAB><verdict><TAB><investor yes|no>
    printf 'idea\t%s\t%s\t%s\t%s\n' "$name" "$(fdate "$d/brief.md")" "$(verdict "$d/brief.md")" "$inv"
    n=$((n + 1))
  done
  [ "$n" -gt 0 ] || printf 'ideas\tnone\n'
}

# ------------------------------------------------------------------ brand --

cmd_brand() {
  local state="$BRAND/state.json" f m status completed="" inprog="" next="" n_done=0 n_all=0

  printf 'dir\t%s\n' "$(rel "$BRAND")"
  if [ -f "$state" ]; then
    # One python3 call turns the checkpoint into tab lines; a broken file says so
    # instead of aborting the report.
    local parsed
    if parsed="$(python3 - "$state" <<'PY' 2>/dev/null
import json, sys
s = json.load(open(sys.argv[1]))
def v(x): return "-" if x in (None, "", []) else x
print("completed\t" + ",".join(s.get("completedModules") or []))
print("in_progress\t" + str(v(s.get("inProgressModule"))))
print("next_module\t" + str(v(s.get("nextModule"))))
print("participants\t" + ",".join(s.get("participants") or []))
print("last_updated\t" + str(v(s.get("lastUpdated"))))
PY
)"; then
      printf 'state\t%s\tpresent\t%s\n' "$(rel "$state")" "$(fdate "$state")"
      completed="$(printf '%s\n' "$parsed" | awk -F'\t' '$1=="completed"{print $2}')"
      inprog="$(printf '%s\n' "$parsed" | awk -F'\t' '$1=="in_progress"{print $2}')"
      next="$(printf '%s\n' "$parsed" | awk -F'\t' '$1=="next_module"{print $2}')"
      printf '%s\n' "$parsed" | grep -vE '^completed'
    else
      printf 'state\t%s\tinvalid\t%s\n' "$(rel "$state")" "$(fdate "$state")"
    fi
  else
    printf 'state\t%s\tmissing\t-\n' "$(rel "$state")"
  fi

  # module<TAB><file><TAB>done|in-progress|written|pending<TAB><date | ->
  # `written` is a module file the checkpoint does not count yet.
  for f in "$BRAND_REFS"/[0-9][0-9]_*.md; do
    [ -f "$f" ] || continue
    m="$(basename "$f")"
    n_all=$((n_all + 1))
    if printf ',%s,' "$completed" | grep -qF ",$m,"; then
      status=done; n_done=$((n_done + 1))
    elif [ "$m" = "$inprog" ]; then
      status=in-progress
    elif [ -f "$BRAND/modules/$m" ]; then
      status=written
    else
      status=pending
    fi
    printf 'module\t%s\t%s\t%s\n' "$m" "$status" "$(fdate "$BRAND/modules/$m")"
  done
  printf 'modules_done\t%s/%s\n' "$n_done" "$n_all"

  local n=0
  for f in "$BRAND"/founders/*.md; do [ -f "$f" ] && n=$((n + 1)); done
  printf 'founder_files\t%s\n' "$n"
  file_row voice "$BRAND/voice.md"
}

# brand_positioning - the best positioning statement branding has: the brandbook,
# then the positioning module, else `-`. /market compete and /decide read it.
brand_positioning() {
  if [ -f "$BRAND/modules/90_SYNTHESIS.md" ]; then rel "$BRAND/modules/90_SYNTHESIS.md"
  elif [ -f "$BRAND/modules/20_positioning.md" ]; then rel "$BRAND/modules/20_positioning.md"
  else printf -- '-\n'; fi
}

# ----------------------------------------------------------------- market --

# stale_if_older <file> <than...> - one `stale` line per input written after it.
stale_if_older() {
  local f="$1" o; shift
  [ -f "$f" ] || return 0
  for o in "$@"; do
    [ -f "$o" ] && [ "$f" -ot "$o" ] \
      && printf 'stale\t%s\tolder than %s\n' "$(rel "$f")" "$(rel "$o")"
  done
}

cmd_market() {
  local f n=0 newest=""
  printf 'dir\t%s\n' "$(rel "$MARKET")"
  file_row scan "$MARKET/scan.md"
  file_row scope "$MARKET/compete/scope.md"
  for f in "$MARKET"/compete/cards/*.md; do
    [ -f "$f" ] || continue
    n=$((n + 1))
    { [ -z "$newest" ] || [ "$newest" -ot "$f" ]; } && newest="$f"
  done
  printf 'cards\t%s\t%s\n' "$(rel "$MARKET/compete/cards")" "$n"
  file_row compete_report "$MARKET/compete/report.md"
  file_row brief "$MARKET/brief.md"
  printf 'positioning\t%s\n' "$(brand_positioning)"
  printf 'project_spec\t%s\n' "$( [ -d "$ROOT/project" ] && rel "$ROOT/project" || printf -- '-' )"

  stale_if_older "$MARKET/compete/report.md" "$MARKET/compete/scope.md" ${newest:+"$newest"}
  stale_if_older "$MARKET/brief.md" "$MARKET/scan.md" "$MARKET/compete/report.md"
}

# ----------------------------------------------------------------- decide --

cmd_decide() {
  local d
  cmd_ideas
  printf 'brand_modules_done\t%s\n' "$(cmd_brand | awk -F'\t' '$1=="modules_done"{print $2}')"
  printf 'positioning\t%s\n' "$(brand_positioning)"
  file_row voice "$BRAND/voice.md"
  file_row market_brief "$MARKET/brief.md"
  file_row scan "$MARKET/scan.md"
  file_row compete_report "$MARKET/compete/report.md"
  file_row decide "$DECIDE"
  # Inputs written after decide.md: the decision predates the evidence.
  if [ -f "$DECIDE" ]; then
    for d in "$IDEAS"/*/brief.md "$BRAND/modules/90_SYNTHESIS.md" "$MARKET/brief.md" \
             "$MARKET/scan.md" "$MARKET/compete/report.md"; do
      [ -f "$d" ] && [ "$DECIDE" -ot "$d" ] && printf 'newer\t%s\t%s\n' "$(rel "$d")" "$(fdate "$d")"
    done
  fi
}

# ------------------------------------------------------------------ slash --

cmd_slash() {
  local cmd="${1:-}" sub="${2:-}"
  case "$cmd" in
    idea)
      printf 'mode\tidea\n'
      printf 'today\t%s\n' "$(date +%Y-%m-%d)"
      printf 'ideas_dir\t%s\n' "$(rel "$IDEAS")"
      cmd_ideas ;;
    brand)
      case "$sub" in
        ""|status) printf 'mode\tbrand-status\n' ;;
        discover|voice) printf 'mode\tbrand-%s\n' "$sub" ;;
        *) printf 'mode\tbrand-unknown\t%s\n' "$sub" ;;
      esac
      printf 'today\t%s\n' "$(date +%Y-%m-%d)"
      cmd_brand ;;
    market)
      case "$sub" in
        "") printf 'mode\tmarket-status\n' ;;
        scan|compete|report) printf 'mode\tmarket-%s\n' "$sub" ;;
        *) printf 'mode\tmarket-unknown\t%s\n' "$sub" ;;
      esac
      printf 'today\t%s\n' "$(date +%Y-%m-%d)"
      cmd_market ;;
    decide)
      printf 'mode\tdecide\n'
      printf 'today\t%s\n' "$(date +%Y-%m-%d)"
      cmd_decide ;;
    *) printf 'mode\tunknown\t%s\n' "$cmd"; usage ;;
  esac
}

case "${1:-}" in
  idea)   shift; cmd_idea "$@" ;;
  ideas)  cmd_ideas ;;
  brand)  cmd_brand ;;
  market) cmd_market ;;
  decide) cmd_decide ;;
  slash)  shift; cmd_slash "$@" ;;
  -h|--help|"") usage ;;
  *) printf 'error\tunknown command %s\n' "$1"; usage ;;
esac
exit 0
