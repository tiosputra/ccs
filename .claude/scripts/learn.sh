#!/usr/bin/env bash
#
# learn.sh - what the workspace has learned about each repo, and whether it still holds.
#
# A skill is a method: it works in any codebase. What applying it to one repo
# takes - which logger, which test runner - is learned once, written to
# .claude/learned/<repo>/<skill>.md, and read on every later load instead of
# re-scanning the repo. This script owns the facts about those files: which
# exist, when they were learned, and whether the code they describe has moved.
#
# Usage:
#   learn.sh status [skill]              every learning skill x workable repo
#   learn.sh fingerprint <skill> <repo>  the fingerprint the repo has now
#   learn.sh stamp <skill> <repo>        write today's date and fingerprint into the learned file
#   learn.sh slash <args...>             dispatcher for the /learn command
#
# Read-only except `stamp`, which rewrites two frontmatter lines of one learned file.
#
# status rows:
#   learned<TAB>skill<TAB>repo<TAB>state<TAB>learned-date<TAB>reviewed<TAB>fingerprint-now
# state is fresh, stale (watched code changed), unstamped, or missing.
#
# A fingerprint hashes the union of two watch lists, one entry per line:
#   the skill's metadata.fingerprint  - generic, well-known library names
#   the learned file's watch          - what the scan found this repo depends on
# Entry forms:
#   lines <file> <regex>   lines of <file> (repo-relative) matching the ERE
#   files <name-glob>      every file so named; node_modules, vendor, .git excluded

# No `set -e`: status is a report, and a grep that matches nothing is a value here.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLAUDE_DIR="$ROOT/.claude"
LEARNED="$CLAUDE_DIR/learned"
. "$SCRIPT_DIR/config.sh"
cfg_resolve REFERENCE_REPOS ""

usage() { sed -n '3,28p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
die()   { printf 'error\t%s\n' "$*" >&2; exit 1; }
rel()   { printf '%s\n' "${1#"$ROOT"/}"; }

# ------------------------------------------------------------------- repos --

# The same rule as space.sh: a comma list of aliases, whitespace ignored.
is_reference_repo() {
  case ",${REFERENCE_REPOS//[[:space:]]/}," in *",$1,"*) return 0 ;; esac
  return 1
}

has_checkouts() {
  local d
  for d in "$ROOT"/repos/*/; do [ -e "$d/.git" ] && return 0; done
  return 1
}

# Workable repos: every checkout under repos/ that is not reference-only. A
# project with no repos/ is its own single repo, named after its directory -
# that is what lets the same skills run in an ordinary repository.
repo_names() {
  local d n
  if has_checkouts; then
    for d in "$ROOT"/repos/*/; do
      [ -e "$d/.git" ] || continue
      n="$(basename "$d")"
      is_reference_repo "$n" || printf '%s\n' "$n"
    done
  else
    basename "$ROOT"
  fi
}

repo_dir() {
  if has_checkouts; then
    [ -e "$ROOT/repos/$1/.git" ] && printf '%s\n' "$ROOT/repos/$1"
  elif [ "$1" = "$(basename "$ROOT")" ]; then
    printf '%s\n' "$ROOT"
  fi
}

# ------------------------------------------------------------- frontmatter --

# A file's YAML frontmatter, without its --- fences. Nothing if it has none.
frontmatter() {
  [ -f "$1" ] || return 1
  awk 'NR == 1 { if ($0 != "---") exit; next } /^---$/ { exit } { print }' "$1"
}

# fm_value <file> <key> - a top-level scalar.
fm_value() { frontmatter "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -1; }

# fm_list <file> <key> - the "- item" lines under <key>, at any indent.
fm_list() {
  frontmatter "$1" | awk -v k="$2" '
    $0 ~ "^[[:space:]]*" k ":[[:space:]]*$" { on = 1; next }
    on && /^[[:space:]]*- / { sub(/^[[:space:]]*- /, ""); print; next }
    on { exit }'
}

skill_file()   { printf '%s\n' "$CLAUDE_DIR/skills/$1/SKILL.md"; }
learned_file() { printf '%s\n' "$LEARNED/$2/$1.md"; }            # <skill> <repo>

skill_learns() {
  frontmatter "$(skill_file "$1")" 2>/dev/null \
    | grep -qE '^[[:space:]]*learns:[[:space:]]*true[[:space:]]*$'
}

learning_skills() {
  local f s
  for f in "$CLAUDE_DIR"/skills/*/SKILL.md; do
    s="$(basename "$(dirname "$f")")"
    skill_learns "$s" && printf '%s\n' "$s"
  done
}

# Prints why <skill> <repo> cannot be learned, and succeeds, if it cannot.
pair_problem() {
  local skill="$1" repo="$2"
  [ -f "$(skill_file "$skill")" ] || { echo "no skill named '$skill'"; return 0; }
  skill_learns "$skill" || { echo "'$skill' does not learn - its frontmatter has no 'learns: true'"; return 0; }
  [ -f "$CLAUDE_DIR/skills/$skill/discover.md" ] \
    || { echo "'$skill' learns but has no discover.md - nothing says what to look for"; return 0; }
  if is_reference_repo "$repo"; then
    echo "'$repo' is reference-only - nobody writes code there, so there is nothing to learn for"; return 0
  fi
  [ -n "$(repo_dir "$repo")" ] \
    || { echo "no workable repo named '$repo' - workable: $(repo_names | tr '\n' ' ')"; return 0; }
  return 1
}

# ------------------------------------------------------------- fingerprint --

digest() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 1; else sha1sum; fi | cut -c1-12
}

# The watched content of one repo, hashed. The entries go into the hash too, so
# editing a watch list makes the file stale until it is re-stamped.
fingerprint() {
  local skill="$1" repo="$2" dir kind arg rest f
  dir="$(repo_dir "$repo")"
  [ -n "$dir" ] || return 1
  { fm_list "$(skill_file "$skill")" fingerprint
    fm_list "$(learned_file "$skill" "$repo")" watch 2>/dev/null
  } | while read -r kind arg rest; do
        printf '== %s %s %s\n' "$kind" "$arg" "$rest"
        case "$kind" in
          lines)
            if [ -f "$dir/$arg" ]; then grep -E -- "$rest" "$dir/$arg"; else echo "(absent)"; fi ;;
          files)
            find "$dir" \( -name node_modules -o -name vendor -o -name .git -o -name dist -o -name .next \) \
                 -prune -o -type f -name "$arg" -print | LC_ALL=C sort | while read -r f; do
              printf -- '-- %s\n' "${f#"$dir"/}"
              cat "$f"
            done ;;
          *) echo "(unknown entry kind: $kind)" ;;
        esac
      done | digest
}

# ------------------------------------------------------------------ status --

status_row() {
  local skill="$1" repo="$2" f now rec state date rev
  f="$(learned_file "$skill" "$repo")"
  now="$(fingerprint "$skill" "$repo")"
  if [ ! -f "$f" ]; then
    state=missing date=- rev=-
  else
    rec="$(fm_value "$f" fingerprint)"
    date="$(fm_value "$f" learned)"
    case "$(fm_value "$f" reviewed)" in yes|true) rev=reviewed ;; *) rev=unreviewed ;; esac
    if [ -z "$rec" ] || [ "$rec" = pending ]; then state=unstamped
    elif [ "$rec" = "$now" ]; then state=fresh
    else state=stale
    fi
    [ -n "$date" ] || date=-
  fi
  printf 'learned\t%s\t%s\t%s\t%s\t%s\t%s\n' "$skill" "$repo" "$state" "$date" "$rev" "$now"
}

cmd_status() {
  local only="${1:-}" skill repo
  [ -z "$only" ] || skill_learns "$only" \
    || die "'$only' is not a skill that learns (no 'learns: true' in its frontmatter)"
  for skill in $(learning_skills); do
    [ -z "$only" ] || [ "$skill" = "$only" ] || continue
    for repo in $(repo_names); do status_row "$skill" "$repo"; done
  done
}

cmd_stamp() {
  local skill="$1" repo="$2" f fp today tmp
  f="$(learned_file "$skill" "$repo")"
  [ -f "$f" ] || die "no learned file at $(rel "$f") - write it first"
  frontmatter "$f" | grep -q '^fingerprint:' || die "$(rel "$f") has no 'fingerprint:' frontmatter line"
  frontmatter "$f" | grep -q '^learned:'     || die "$(rel "$f") has no 'learned:' frontmatter line"
  fp="$(fingerprint "$skill" "$repo")"
  today="$(date +%Y-%m-%d)"
  tmp="$f.tmp.$$"
  awk -v fp="$fp" -v d="$today" '
    NR == 1 && $0 == "---" { fm = 1; print; next }
    fm && $0 == "---"      { fm = 0 }
    fm && /^fingerprint:/  { print "fingerprint: " fp; next }
    fm && /^learned:/      { print "learned: " d; next }
    { print }' "$f" > "$tmp" && mv "$tmp" "$f"
  printf 'stamped\t%s\t%s\t%s\t%s\n' "$skill" "$repo" "$today" "$fp"
}

# ------------------------------------------------------------------- slash --

cmd_slash() {
  local skill repo msg
  if [ $# -eq 0 ] || [ "$1" = status ]; then
    [ $# -gt 0 ] && shift
    printf 'mode\tstatus\n'
    if [ $# -gt 0 ] && ! skill_learns "$1"; then
      printf 'error\t%s\n' "'$1' is not a skill that learns"; return
    fi
    cmd_status "${1:-}"
    return
  fi
  if [ $# -eq 1 ]; then
    if skill_learns "$1"; then printf 'mode\tstatus\n'; cmd_status "$1"; return; fi
    printf 'mode\terror\nerror\t%s\n' "'$1' is not a skill that learns - usage: /learn [status] | <skill> <repo>"
    return
  fi
  skill="$1" repo="$2"
  if msg="$(pair_problem "$skill" "$repo")"; then
    printf 'mode\terror\nerror\t%s\n' "$msg"; return
  fi
  printf 'mode\tlearn\n'
  printf 'skill\t%s\n'        "$skill"
  printf 'repo\t%s\n'         "$repo"
  printf 'repo_dir\t%s\n'     "$(rel "$(repo_dir "$repo")")"
  printf 'discover\t%s\n'     "$(rel "$CLAUDE_DIR/skills/$skill/discover.md")"
  printf 'learned_file\t%s\n' "$(rel "$(learned_file "$skill" "$repo")")"
  status_row "$skill" "$repo"
  printf 'stamp\t%s\n' ".claude/scripts/learn.sh stamp $skill $repo"
}

# -------------------------------------------------------------------- main --

case "${1:-}" in
  status)
    shift; cmd_status "${1:-}" ;;
  fingerprint|stamp)
    [ $# -eq 3 ] || { usage; exit 2; }
    if msg="$(pair_problem "$2" "$3")"; then die "$msg"; fi
    if [ "$1" = fingerprint ]; then fingerprint "$2" "$3"; else cmd_stamp "$2" "$3"; fi ;;
  slash)
    shift; cmd_slash ${1+"$@"} ;;
  ""|-h|--help|help)
    usage ;;
  *)
    usage; exit 2 ;;
esac
