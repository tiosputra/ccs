#!/usr/bin/env bash
#
# ccs.sh - health check and improvement notes for the workspace system itself.
#
# space.sh looks after tasks. This one looks after the thing that runs tasks:
# the commands, skills, scripts and rules under .claude/, and whether they
# still describe the workspace as it actually is.
#
# Read-only except `note`, which appends one line to .claude/ccs-notes.md.
#
# Usage:
#   ccs.sh check                 run every check, print findings
#   ccs.sh note <text>           record one line of friction, dated
#   ccs.sh notes                 print recorded notes
#   ccs.sh slash <args...>       dispatcher for the /ccs command
#
# Findings are printed as:
#   finding<TAB><high|med|low><TAB><area><TAB><message>
# and clean areas as:
#   ok<TAB><area><TAB><message>

# No `set -e`: a health check that aborts on the first grep that matches
# nothing reports less than no health check at all. Failures are values here.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLAUDE_DIR="$ROOT/.claude"
NOTES="$CLAUDE_DIR/ccs-notes.md"
. "$SCRIPT_DIR/config.sh"
cfg_resolve SPACE_BRANCH_PREFIX ccs
BRANCH_PREFIX="$SPACE_BRANCH_PREFIX"

usage() { sed -n '3,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

finding() { printf 'finding\t%s\t%s\t%s\n' "$1" "$2" "$3"; }
ok()      { printf 'ok\t%s\t%s\n' "$1" "$2"; }

# Prose files that are supposed to describe the workspace to a reader.
DOCS="$ROOT/README.md $ROOT/CLAUDE.md $CLAUDE_DIR/commands/space.md"

# Repo directory names, read from disk - the same rule space.sh uses.
all_repo_names() {
  local d
  for d in "$ROOT"/repos/*/; do
    [ -e "$d/.git" ] || continue
    basename "$d"
  done
}

# ------------------------------------------------------------------ checks --

check_repos() {
  local n repo doc name bad=0
  n="$(all_repo_names | wc -l | tr -d ' ')"

  # The roster is read from disk on purpose, so the check is not "is every
  # repo listed" - nothing lists them. It is "do the docs still send a reader
  # to the live roster, and do they name any service that no longer exists".
  for doc in "$ROOT/README.md" "$CLAUDE_DIR/commands/space.md"; do
    [ -f "$doc" ] || continue
    grep -qE '(/space|space\.sh) repos' "$doc" \
      || { finding med repos "${doc#$ROOT/} never points at '/space repos' - a reader has no way to learn what is checked out"; bad=$((bad+1)); }
  done

  # A doc naming repos/<something> that is not on disk: a stale example, or a
  # service that was removed and left a dangling reference behind.
  for name in $(grep -rhoE 'repos/[a-z][a-z0-9-]*' \
                  "$ROOT/README.md" "$ROOT/CLAUDE.md" "$CLAUDE_DIR"/commands/*.md \
                  "$CLAUDE_DIR"/skills/*/SKILL.md 2>/dev/null \
                | sed 's|repos/||' | sort -u); do
    case "$name" in readme|README) continue;; esac
    if [ ! -d "$ROOT/repos/$name" ]; then
      finding high repos "a doc references repos/$name, which is not checked out"
      bad=$((bad + 1))
    fi
  done

  [ "$bad" -eq 0 ] && ok repos "$n checkout(s) on disk; docs defer to the live roster and name no missing service"
}

check_scripts() {
  local f name refs bad=0
  for f in "$CLAUDE_DIR"/scripts/*.sh; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    if ! bash -n "$f" 2>/dev/null; then
      finding high scripts "$name has a syntax error"
      bad=$((bad + 1))
      continue
    fi
    [ -x "$f" ] || { finding med scripts "$name is not executable"; bad=$((bad + 1)); }
    # Match the bare filename, not just "scripts/<name>": a library script is
    # reached by `. "$SCRIPT_DIR/config.sh"`, which names no directory.
    refs="$( { grep -rl -- "$name" "$CLAUDE_DIR" "$ROOT/README.md" "$ROOT/CLAUDE.md" 2>/dev/null || true; } \
            | grep -v "^$f\$" | wc -l | tr -d ' ')"
    if [ "$refs" -eq 0 ]; then
      finding med scripts "$name is referenced by no command, skill or doc - nothing invokes it"
      bad=$((bad + 1))
    fi
  done
  [ "$bad" -eq 0 ] && ok scripts "every script parses, is executable, and is referenced"
}

check_commands() {
  local f name bad=0 ref
  for f in "$CLAUDE_DIR"/commands/*.md; do
    [ -f "$f" ] || continue
    name="/$(basename "$f" .md)"
    head -1 "$f" | grep -q '^---$' \
      || { finding high commands "$name has no frontmatter"; bad=$((bad+1)); continue; }
    grep -q '^description:' "$f" \
      || { finding high commands "$name has no description - it will show blank in the picker"; bad=$((bad+1)); }
    grep -q '^allowed-tools:' "$f" \
      || { finding med commands "$name declares no allowed-tools - every call prompts"; bad=$((bad+1)); }
    # A command that eagerly runs a script must name a script that exists.
    for ref in $(grep -ohE '\.claude/scripts/[a-z0-9-]+\.sh' "$f" | sort -u); do
      [ -f "$ROOT/$ref" ] || { finding high commands "$name calls $ref, which does not exist"; bad=$((bad+1)); }
    done
  done
  [ "$bad" -eq 0 ] && ok commands "every command has frontmatter and calls only scripts that exist"
}

check_skills() {
  local d name declared bad=0 s
  for d in "$CLAUDE_DIR"/skills/*/; do
    [ -f "$d/SKILL.md" ] || { finding high skills "$(basename "$d")/ has no SKILL.md"; bad=$((bad+1)); continue; }
    name="$(basename "$d")"
    declared="$(sed -n 's/^name: *//p' "$d/SKILL.md" | head -1)"
    [ "$declared" = "$name" ] \
      || { finding high skills "skills/$name declares name: '$declared' - the directory name must match"; bad=$((bad+1)); }
    grep -q '^description:' "$d/SKILL.md" \
      || { finding high skills "skills/$name has no description - it will never auto-trigger"; bad=$((bad+1)); }
  done

  # Skills named in prose that do not exist. A dangling pointer sends a session
  # looking for guidance that was never written.
  for s in $(grep -rhoE '`[a-z][a-z0-9]*(-[a-z0-9]+)+`' "$CLAUDE_DIR"/skills/*/SKILL.md \
             "$CLAUDE_DIR"/commands/*.md "$ROOT/CLAUDE.md" 2>/dev/null \
             | tr -d '`' | grep -E -- '-(patterns|standards|workflow|design|conventions)$' | sort -u); do
    [ -d "$CLAUDE_DIR/skills/$s" ] || { finding med skills "'$s' is referenced but no such skill exists"; bad=$((bad+1)); }
  done
  [ "$bad" -eq 0 ] && ok skills "every skill is well-formed and every reference resolves"
}

check_docs_commands() {
  local c bad=0
  for c in $(grep -rhoE '(^|[ `(])/[a-z][a-z0-9-]{2,}' \
               "$ROOT/README.md" "$ROOT/CLAUDE.md" "$CLAUDE_DIR"/commands/*.md \
               "$CLAUDE_DIR"/skills/*/SKILL.md 2>/dev/null \
             | tr -d ' `(' | sed 's|^/||' | sort -u); do
    [ -f "$CLAUDE_DIR/commands/$c.md" ] && continue
    # Skills and built-ins are invoked the same way; only flag names that look
    # like this workspace's own commands and have no file.
    case "$c" in
      space|plan|plan-prd|pr|ccs) ;;
      *) continue ;;
    esac
    finding high commands "docs reference /$c but .claude/commands/$c.md does not exist"
    bad=$((bad + 1))
  done
  [ "$bad" -eq 0 ] && ok docs "every workspace command named in the docs exists"
}

check_settings() {
  local f="$CLAUDE_DIR/settings.json" ref bad=0
  [ -f "$f" ] || { finding med settings "no settings.json"; return 0; }
  python3 -c "import json,sys;json.load(open('$f'))" 2>/dev/null \
    || { finding high settings "settings.json is not valid JSON"; return 0; }
  for ref in $(grep -ohE '\.claude/scripts/[a-z0-9-]+\.sh' "$f" | sort -u); do
    [ -f "$ROOT/$ref" ] || { finding med settings "a permission allows $ref, which does not exist"; bad=$((bad+1)); }
  done
  grep -q 'guard.sh' "$f" || { finding high settings "guard.sh is not wired as a PreToolUse hook - repos/ is unprotected"; bad=$((bad+1)); }
  [ "$bad" -eq 0 ] && ok settings "valid, guard wired, permissions point at real scripts"
}

check_guard() {
  # The guard is the only enforcement in the workspace, and it is regexes over
  # raw command text - so the check is not "does it exist" but "does it still
  # block what it must and pass what it must". guard-test.sh holds the cases;
  # a failure names them.
  local t="$SCRIPT_DIR/guard-test.sh" out
  [ -x "$t" ] || { finding med guard "guard-test.sh is missing - the guard's behaviour is unpinned"; return 0; }
  out="$("$t" -q 2>/dev/null | tail -1)"
  case "$out" in
    *fail=0) ok guard "${out%%	*} guard cases pass - repos/ sealed, reads unblocked" ;;
    *)       finding high guard "guard-test.sh reports $out - run .claude/scripts/guard-test.sh for the failing cases" ;;
  esac
}

check_config() {
  # Per-machine settings live in a gitignored .env. The check is not "is the
  # prefix ccs" - there is no right value any more - it is whether the
  # mechanism still works: a template exists, it lists every setting the
  # scripts read, and nobody has committed their own .env.
  local bad=0 var
  if [ ! -f "$ROOT/.env.example" ]; then
    finding high config ".env.example is missing - nothing tells a new machine what is configurable"
    bad=$((bad + 1))
  else
    for var in $(grep -rhoE 'cfg_resolve +[A-Z_]+' "$CLAUDE_DIR"/scripts/*.sh 2>/dev/null \
                 | awk '{print $2}' | sort -u); do
      grep -qE "^[[:space:]]*#?[[:space:]]*$var[[:space:]]*=" "$ROOT/.env.example" \
        || { finding med config "$var is resolved by a script but absent from .env.example"; bad=$((bad+1)); }
    done
  fi
  if git -C "$ROOT" ls-files --error-unmatch .env >/dev/null 2>&1; then
    finding high config ".env is tracked in git - one person's settings would become everyone's"
    bad=$((bad + 1))
  fi
  [ "$bad" -eq 0 ] && ok config "prefix '$BRANCH_PREFIX' (from $(cfg_source SPACE_BRANCH_PREFIX)); .env.example documents every setting and .env is untracked"
}

check_doc_prefix() {
  # No tracked file may name a branch prefix: it differs per machine, so a
  # literal is wrong for everyone but its author. Docs write <prefix>/<task>.
  local f hit bad=0
  for f in "$ROOT/CLAUDE.md" "$ROOT/README.md" "$CLAUDE_DIR"/commands/*.md \
           "$CLAUDE_DIR"/skills/*/SKILL.md; do
    [ -f "$f" ] || continue
    for hit in $(grep -ohE '[a-z][a-z0-9-]*/<task>' "$f" 2>/dev/null | sort -u); do
      case "${hit%%/*}" in
        spaces|repos|docs|release|testing) continue ;;
      esac
      finding med docs "${f#$ROOT/} hardcodes '$hit' - the prefix is per machine, write '<prefix>/<task>'"
      bad=$((bad + 1))
    done
  done
  [ "$bad" -eq 0 ] && ok docs "no tracked file names a branch prefix"
}

check_branch_prefix() {
  # Open work only. A closed task's PRD, plan and log record what happened
  # under whatever prefix applied then; rewriting them to satisfy a check
  # would be falsifying the record, so they are skipped. A task is closed once
  # its directory holds a log.md - that is written just before teardown.
  local d f task pfx bad=0
  for d in "$ROOT"/docs/*_*/; do
    [ -d "$d" ] || continue
    [ -f "$d/log.md" ] && continue
    task="$(basename "$d")"; task="${task#*_}"
    [ -n "$task" ] || continue
    for f in "$d"prd.md "$d"plan*.md; do
      [ -f "$f" ] || continue
      for pfx in $(grep -ohE "[a-z][a-z0-9-]*/$task\b" "$f" 2>/dev/null | sed 's|/.*||' | sort -u); do
        # Path segments, not branch prefixes: a plan naming
        # docs/testing/... must not read as a branch called 'testing'.
        # The .claude/ subdirectories are here for the same reason - machinery
        # work is named after the artifact it builds, so a PRD for a command
        # called X legitimately writes commands/X and scripts/X.
        case "$pfx" in origin|refs|remotes|spaces|repos|docs|testing|release|commands|scripts|skills|agents) continue;; esac
        if [ "$pfx" != "$BRANCH_PREFIX" ]; then
          finding med branch "${f#$ROOT/} names the branch '$pfx/$task', but this machine resolves '$BRANCH_PREFIX/' - a PRD should say '<prefix>/<task>'"
          bad=$((bad + 1))
        fi
      done
    done
  done
  [ "$bad" -eq 0 ] && ok branch "no open task artifact pins a branch prefix"
}

check_legacy_branches() {
  # Task branches left over from an earlier prefix. `for-each-ref` gives a
  # stable machine-readable format, which is why it is used here; the guard now
  # also permits `git branch --list` against repos/. These branches are the
  # user's to rename or delete - some carry commits that exist on no remote -
  # so they are reported, never touched.
  local tasks task repo ref pfx bad=0
  tasks="$( { ls -d "$ROOT"/docs/*_*/ 2>/dev/null || true; } \
            | sed -e 's|/$||' -e 's|.*/||' -e 's|^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}_||' \
            | sort -u)"
  for repo in $(all_repo_names); do
    while read -r ref; do
      [ -n "$ref" ] || continue
      pfx="${ref%%/*}"; task="${ref#*/}"
      [ "$pfx" = "$BRANCH_PREFIX" ] && continue
      case "$pfx" in feature|release|hotfix|bugfix|main|master|develop|dev|staging) continue;; esac
      printf '%s\n' "$tasks" | grep -qx -- "$task" || continue
      finding low legacy "repos/$repo still has '$ref' - a task branch under an older prefix than '$BRANCH_PREFIX/'"
      bad=$((bad + 1))
    done <<EOF
$(git -C "$ROOT/repos/$repo" for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null || true)
EOF
  done
  [ "$bad" -eq 0 ] && ok legacy "no task branches left under an older prefix"
}

check_artifacts() {
  # One task, one directory: docs/<YYYY-MM-DD>_<task>/ holding prd.md, plan.md,
  # plan-m<N>.md, api-contract.md, testing.md and log.md. Anything else in docs/ is a stray.
  local log d f name task bad=0 space entry
  for entry in "$ROOT"/docs/*; do
    [ -e "$entry" ] || continue
    name="$(basename "$entry")"
    [ "$name" = "README.md" ] && continue
    if [ ! -d "$entry" ]; then
      finding med artifacts "docs/$name is a loose file - every task artifact belongs in docs/<YYYY-MM-DD>_<task>/"
      bad=$((bad + 1))
      continue
    fi
    case "$name" in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]_?*) ;;
      *) finding med artifacts "docs/$name is not named <YYYY-MM-DD>_<task> - the date is the day the task opened"
         bad=$((bad + 1)); continue ;;
    esac
    for f in "$entry"/*; do
      [ -e "$f" ] || continue
      case "$(basename "$f")" in
        prd.md|plan.md|log.md|testing.md|api-contract.md|plan-m[0-9]*.md) ;;
        *) finding low artifacts "docs/$name/$(basename "$f") is not one of prd.md, plan.md, plan-m<N>.md, api-contract.md, testing.md, log.md"
           bad=$((bad + 1)) ;;
      esac
    done
  done
  for log in "$ROOT"/docs/*_*/log.md; do
    [ -f "$log" ] || continue
    d="$(dirname "$log")"; name="$(basename "$d")"; task="${name#*_}"
    if [ ! -f "$d/prd.md" ]; then
      finding low artifacts "docs/$name/log.md has no prd.md - '$task' ran outside the documented flow"
      bad=$((bad + 1))
    fi
  done
  for space in "$ROOT"/spaces/*/; do
    [ -d "$space" ] || continue
    task="$(basename "$space")"
    [ "$task" = "README.md" ] && continue
    [ -f "$space/.space" ] || finding med artifacts "spaces/$task has no .space metadata - report and teardown will be thin"
    if [ -z "$(find "$space" -mindepth 1 -maxdepth 1 -not -name '.space' 2>/dev/null)" ]; then
      finding med artifacts "spaces/$task holds no worktree - an orphan left by a failed teardown"
      bad=$((bad + 1))
    fi
  done
  [ "$bad" -eq 0 ] && ok artifacts "every task doc sits in docs/<date>_<task>/, logs trace back to PRDs, no orphan spaces"
}

check_notes() {
  local n=0
  # `grep -c` prints 0 and exits 1 when nothing matches, so a `|| echo 0`
  # fallback appends a second line and breaks the comparison below.
  [ -f "$NOTES" ] && n="$(grep -c '^- \[ \]' "$NOTES" 2>/dev/null)"
  [ -n "$n" ] || n=0
  if [ "$n" -gt 0 ]; then
    printf 'notes\t%s\topen improvement notes recorded during real runs\n' "$n"
  else
    ok notes "nothing recorded - use '/ccs note <what got in the way>' during a task"
  fi
}

cmd_check() {
  printf 'root\t%s\n' "$ROOT"
  printf 'prefix\t%s\t%s\n\n' "$BRANCH_PREFIX" "from $(cfg_source SPACE_BRANCH_PREFIX)"
  check_repos
  check_scripts
  check_commands
  check_skills
  check_settings
  check_guard
  check_docs_commands
  check_config
  check_doc_prefix
  check_branch_prefix
  check_legacy_branches
  check_artifacts
  check_notes
}

# ------------------------------------------------------------------- notes --

cmd_note() {
  local text="$*"
  [ -n "$text" ] || { echo "nothing to record - ccs.sh note <text>" >&2; exit 1; }
  if [ ! -f "$NOTES" ]; then
    cat >"$NOTES" <<'HDR'
# ccs notes

Friction found while running real tasks, recorded in the moment so it is still
true when someone reads it. One line each; `/ccs` turns them into a worklist.

Written by `.claude/scripts/ccs.sh note`. Tick a line off when it ships.

HDR
  fi
  printf -- '- [ ] %s — %s\n' "$(date '+%Y-%m-%d')" "$text" >>"$NOTES"
  printf 'recorded\t%s\n' "${NOTES#$ROOT/}"
  tail -1 "$NOTES"
}

cmd_notes() {
  [ -f "$NOTES" ] || { echo "no notes yet"; return 0; }
  cat "$NOTES"
}

# ------------------------------------------------------------------- slash --

cmd_slash() {
  local sub="${1:-check}"
  case "$sub" in
    note)  shift; printf 'mode\tnote\n\n'; cmd_note "$@" ;;
    notes) shift; printf 'mode\tnotes\n\n'; cmd_notes ;;
    check|"") printf 'mode\tcheck\n\n'; cmd_check ;;
    -h|--help) usage ;;
    *) printf 'mode\tnote\n\n'; cmd_note "$@" ;;
  esac
}

case "${1:-}" in
  ""|-h|--help) usage ;;
  check)  shift; cmd_check ;;
  note)   shift; cmd_note "$@" ;;
  notes)  shift; cmd_notes ;;
  slash)  shift; cmd_slash "$@" ;;
  *) usage; echo "unknown command '$1'" >&2; exit 1 ;;
esac
