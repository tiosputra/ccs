#!/usr/bin/env bash
#
# deployment-notes.sh - deterministic facts about a release, from a stated list
# of branches to compare. /deployment-notes turns them into a dev section (what
# to prepare, in what order, how to undo it) and a QA section (what should be true).
#
# A release is stated, never inferred: one line per service saying which branch
# ships into which, `<service> -> <feature branch> -> <target branch>`, e.g.
# `backend -> feature/gsa -> main`. <service> is a checkout under repos/.
#
# The comparison is local, not a pull request's. `gh pr diff` gives up on a
# large diff, and a release branch is exactly the diff that is too large. So
# `prepare` asks origin for each branch's SHA (ls-remote - the server, not the
# local clone), fetches it, checks the fetched ref is that SHA, and exports it
# as a plain directory under release/<date>-<name>/:
#
#   <service>-target/    the target branch as it is now - what production runs
#   <service>-feature/   the feature branch - what it will run
#   <service>.diff       target...feature: what the feature brings, from the
#                        merge base, exactly as a pull request would show it
#   <service>.files      the same, as numstat - where to start reading
#   <date>-<name>.md     the deployment notes, written by /deployment-notes
#   <date>-<name>.html   the notes as a page, built by `page` and published as
#                        an artifact; artifact.url records where
#
# Three services make six directories. They are exports, not worktrees: no .git,
# nothing to commit from, and nothing in repos/ changes except the two
# remote-tracking refs the fetch updates. A local branch is never compared, and
# a branch origin cannot confirm stops everything - a stale ref has reported a
# repo as having nothing to release before.
#
# What a path means in a given repo - who it faces, where its app keeps its
# route registry - is a fact about that repo, learned once by
# `/learn qa-release-note <repo>` into .claude/learned/<repo>/qa-release-note.md.
# This script reads the two machine-read sections of that file and guesses
# nothing when it is missing: it prints a `learn` record instead. How a repo is
# configured, deployed and rolled back is learned by `/learn dev-deployment-note`;
# no section of that file is machine-read, so the command reads it, not this.
#
# Architecture of a repo NOT in the release - an app's route registry, contract
# copies - is read from a git ref, never a working tree: a task may hold that
# checkout on its own branch. repo_path() is the one way in.
#
# Usage:
#   deployment-notes.sh prepare <name> "<service> -> <feature> -> <target>"...
#                                                   fetch, export, diff, roll call
#   deployment-notes.sh report  <name>              facts + extraction, from the snapshot
#   deployment-notes.sh facts   <service> <diff>    local facts for one saved diff
#   deployment-notes.sh page    <name>              build the shareable page from the notes
#   deployment-notes.sh clean   <name>              remove the snapshot, keep the notes and page
#   deployment-notes.sh slash   <args...>           dispatcher for /deployment-notes
#
# Output is key<TAB>value lines. Multi-field records are documented at the head
# of the section that prints them.

# No `set -e`: a report that aborts on the first grep matching nothing reports
# less than no report at all. Failures are values here, printed as `warn`.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RELEASE_DIR="$ROOT/release"
LEARNED="$ROOT/.claude/learned"
. "$SCRIPT_DIR/tasklib.sh"
TODAY="$(date +%Y-%m-%d)"
TAB="$(printf '\t')"

usage() { sed -n '3,55p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

warn() { printf 'warn\t%s\n' "$1"; }
kv()   { printf '%s\t%s\n' "$1" "$2"; }

WORK=""
cleanup() { [ -n "$WORK" ] && [ -d "$WORK" ] && rm -rf "$WORK"; }
trap cleanup EXIT

# ------------------------------------------------------------------ inputs --

# A spec line -> "<service><TAB><feature><TAB><target>", or nothing.
#
# Lines arrive pasted, so they carry whatever came with them: a leading "- "
# from a markdown list, surrounding whitespace, a unicode arrow. Strip that
# rather than making the caller tidy it.
parse_spec() {
  printf '%s' "$1" \
    | sed -e 's/→/->/g' -e 's/^[[:space:]]*[-*][[:space:]][[:space:]]*//' \
    | awk -F'->' 'NF == 3 {
        for (i = 1; i <= 3; i++) gsub(/^[ \t]+|[ \t]+$/, "", $i)
        if ($1 != "" && $2 != "" && $3 != "") print $1 "\t" $2 "\t" $3
      }'
}

# The ref a repo's architecture is read from: its remote default branch, which
# no task can move. A clone without origin/HEAD falls back to the base commit of
# the in-place task holding it, if any, and only then to HEAD - which, with no
# task holding the checkout, is the branch it was cloned on.
canonical_ref() {
  local dir="$ROOT/repos/$1" t base
  if git -C "$dir" rev-parse --verify --quiet refs/remotes/origin/HEAD >/dev/null; then
    printf '%s' refs/remotes/origin/HEAD; return 0
  fi
  if t="$(task_holding "$1")"; then
    base="$(task_base "$t" "$1")" && { printf '%s' "${base#*	}"; return 0; }
  fi
  printf '%s' HEAD
}

# The one chokepoint for reading a repo outside the snapshot. Takes a repo alias
# and a path inside it, reads that file at canonical_ref, and prints the path of
# a copy in the scratch directory - or prints nothing if the file is not on that
# ref.
#
# Everything local goes through here so the "a ref, never a working tree" rule
# is a property of the script rather than a habit each caller has to remember.
# A caller that builds its own path is a bug; there is no second way in.
repo_path() {
  local al="$1" rel="${2:-}" dir ref out
  case "$al" in ""|-|*/*|.|..) return 1 ;; esac
  case "/$rel/" in */../*|//) return 1 ;; esac
  dir="$ROOT/repos/$al"
  [ -e "$dir/.git" ] || return 1
  ref="$(canonical_ref "$al")"
  git -C "$dir" cat-file -e "$ref:$rel" 2>/dev/null || return 1
  [ -n "$WORK" ] || return 1
  out="$WORK/ref/$al/$rel"
  mkdir -p "$(dirname "$out")" || return 1
  git -C "$dir" show "$ref:$rel" >"$out" 2>/dev/null || return 1
  printf '%s' "$out"
}

# <org>/<repo> from a checkout's origin URL, for gh. Nothing when it is not a
# GitHub remote this can read.
slug_for() {
  git -C "$ROOT/repos/$1" remote get-url origin 2>/dev/null \
    | sed -e 's|\.git$||' -e 's|/$||' \
    | sed -n 's|^.*github\.com[:/]\([^/]*\)/\([^/]*\)$|\1/\2|p'
}

# A branch as the user typed it -> its name on the server. `origin/feature/gsa`,
# `refs/remotes/origin/feature/gsa` and `feature/gsa` all mean the same branch
# on origin; the prefix is how people tell it apart from a local branch, and a
# local branch is never what is compared.
remote_branch() {
  local b="$1"
  b="${b#refs/remotes/origin/}"; b="${b#refs/heads/}"; b="${b#origin/}"
  printf '%s' "$b"
}

# The SHA a branch points at on origin, asked of the server itself - not read
# from any ref in the local clone. Nothing when the server has no such branch
# or cannot be reached.
remote_sha() {
  git -C "$ROOT/repos/$1" ls-remote origin "refs/heads/$2" </dev/null 2>/dev/null \
    | awk -v r="refs/heads/$2" '$2 == r { print $1; exit }'
}

# The snapshot directory for a release name: today's for prepare, the newest
# one on disk for everything else. Only a directory holding a manifest counts -
# that file is what makes it this script's to replace or remove.
snapshot_today() { printf '%s' "$RELEASE_DIR/$TODAY-$1"; }
snapshot_latest() {
  local d last=""
  for d in "$RELEASE_DIR"/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-"$1"/; do
    [ -f "$d/manifest.tsv" ] && last="${d%/}"
  done
  [ -n "$last" ] && printf '%s' "$last"
}

# The newest release directory holding notes for a name - it outlives `clean`.
notes_dir_latest() {
  local d last=""
  for d in "$RELEASE_DIR"/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-"$1"/; do
    [ -f "$d/$(basename "$d").md" ] && last="${d%/}"
  done
  [ -n "$last" ] && printf '%s' "$last"
}

# Remove a snapshot's exports and records, keeping what was written about it:
# the notes, the page, and the artifact link. Re-running prepare on the same day
# and `clean` both come through here, so neither can take the notes with it.
snapshot_wipe() {
  local dir="$1" f
  for f in "$dir"/* "$dir"/.[!.]*; do
    [ -e "$f" ] || continue
    case "$(basename "$f")" in
      *.md|*.html|artifact.url) continue ;;
    esac
    rm -rf "$f"
  done
}

# Where a git diff is printed from. Whatever the user's git config says about
# prefixes, external diff drivers or textconv, the facts below parse `+++ b/`.
gdiff() {
  local dir="$1"; shift
  git -C "$dir" -c core.quotePath=false diff --no-color --no-ext-diff --no-textconv \
    --src-prefix=a/ --dst-prefix=b/ -M "$@"
}

# --------------------------------------------------------------- prepare --

# Every spec is checked, and every branch fetched, before the first directory
# is written: a release with one bad line is refused whole, not half exported.
#
# svc<TAB>service<TAB>feature<TAB>feature-sha<TAB>target<TAB>target-sha<TAB>ahead<TAB>behind<TAB>files<TAB>+a/-d
# source<TAB>service<TAB>org/repo<TAB>origin/feature@sha<TAB>origin/target@sha
# snapshot<TAB>service<TAB>target-dir<TAB>feature-dir<TAB>diff<TAB>files
prepare() {
  local name="$1"; shift
  local spec line svc feature target dir seen="" specs="" bad=0
  local fsha tsha base counts behind ahead files short snap rel b sha got pinned dir

  for spec in "$@"; do
    line="$(parse_spec "$spec")"
    if [ -z "$line" ]; then
      printf 'error\tnot "<service> -> <feature> -> <target>": %s\n' "$spec"; bad=1; continue
    fi
    svc="$(printf '%s' "$line" | cut -f1)"
    feature="$(remote_branch "$(printf '%s' "$line" | cut -f2)")"
    target="$(remote_branch "$(printf '%s' "$line" | cut -f3)")"
    case "$svc" in
      .*|*[!A-Za-z0-9._-]*) printf 'error\tnot a service name: %s\n' "$svc"; bad=1; continue ;;
    esac
    if [ ! -e "$ROOT/repos/$svc/.git" ]; then
      printf 'error\tno checkout at repos/%s - /task repos lists what is here\n' "$svc"; bad=1; continue
    fi
    for b in "$feature" "$target"; do
      git check-ref-format --branch "$b" >/dev/null 2>&1 \
        || { printf 'error\tnot a branch name: %s\n' "$b"; bad=1; }
    done
    # One line per service: the directories are named <service>-feature and
    # <service>-target, so a second line would overwrite the first.
    case " $seen " in
      *" $svc "*) printf 'error\t%s is named twice - give the one branch that carries everything shipping into it\n' "$svc"; bad=1; continue ;;
    esac
    seen="$seen $svc"
    specs="$specs$svc	$feature	$target
"
  done
  [ -n "$specs" ] || { warn "no service lines given - one per line: <service> -> <feature> -> <target>"; return 2; }
  [ "$bad" -eq 0 ] || return 2

  # Every SHA comes from the server. Ask origin what each branch points at,
  # fetch exactly that, and refuse if the fetched ref is anything else - so a
  # local branch, a stale remote-tracking ref or a fetch that silently did
  # nothing can never be what gets compared. Only the remote-tracking refs move.
  pinned=""
  while IFS="$TAB" read -r svc feature target; do
    [ -n "$svc" ] || continue
    dir="$ROOT/repos/$svc"
    fsha="" tsha=""
    for b in "$feature" "$target"; do
      sha="$(remote_sha "$svc" "$b")"
      if [ -z "$sha" ]; then
        printf 'error\t%s: origin has no branch %s, or could not be reached - nothing was written\n' "$svc" "$b"
        bad=1; continue
      fi
      if ! git -C "$dir" fetch --quiet --no-tags origin "+refs/heads/$b:refs/remotes/origin/$b" </dev/null 2>/dev/null; then
        printf 'error\t%s: could not fetch origin/%s - nothing was written\n' "$svc" "$b"
        bad=1; continue
      fi
      got="$(git -C "$dir" rev-parse --verify --quiet "refs/remotes/origin/$b^{commit}")"
      if [ "$got" != "$sha" ]; then
        printf 'error\t%s: origin/%s moved while fetching (%s, then %s) - run again\n' "$svc" "$b" "${sha:0:10}" "${got:0:10}"
        bad=1; continue
      fi
      if [ "$b" = "$feature" ]; then fsha="$sha"; fi
      if [ "$b" = "$target" ]; then tsha="$sha"; fi
    done
    pinned="$pinned$svc	$feature	$target	$fsha	$tsha
"
  done <<EOF
$specs
EOF
  [ "$bad" -eq 0 ] || return 2

  snap="$(snapshot_today "$name")"
  if [ -e "$snap" ]; then
    if [ -f "$snap/manifest.tsv" ] || [ -f "$snap/$(basename "$snap").md" ]; then
      snapshot_wipe "$snap"
    else
      printf 'error\t%s exists and was not made by this script - move it aside\n' "${snap#$ROOT/}"; return 2
    fi
  fi
  mkdir -p "$snap" || return 2
  rel="${snap#$ROOT/}"
  kv snapshot-dir "$rel"

  : > "$snap/rollcall.tsv"
  while IFS="$TAB" read -r svc feature target fsha tsha; do
    [ -n "$svc" ] || continue
    dir="$ROOT/repos/$svc"
    if ! base="$(git -C "$dir" merge-base "$tsha" "$fsha" 2>/dev/null)"; then
      printf 'error\t%s: %s and %s share no history\n' "$svc" "$feature" "$target"; continue
    fi

    mkdir -p "$snap/$svc-target" "$snap/$svc-feature"
    git -C "$dir" archive --format=tar "$tsha" | tar -xf - -C "$snap/$svc-target" \
      || warn "$svc: export of $target was incomplete"
    git -C "$dir" archive --format=tar "$fsha" | tar -xf - -C "$snap/$svc-feature" \
      || warn "$svc: export of $feature was incomplete"
    gdiff "$dir" "$tsha...$fsha" > "$snap/$svc.diff"
    gdiff "$dir" --numstat "$tsha...$fsha" > "$snap/$svc.files"

    counts="$(git -C "$dir" rev-list --left-right --count "$tsha...$fsha")"
    behind="$(printf '%s' "$counts" | awk '{print $1}')"
    ahead="$(printf '%s' "$counts" | awk '{print $2}')"
    files="$(wc -l < "$snap/$svc.files" | tr -d ' ')"
    short="$(awk -F'\t' '$1 != "-" { a += $1; d += $2 } END { printf "+%d/-%d", a, d }' "$snap/$svc.files")"

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$svc" "$feature" "$fsha" "$target" "$tsha" "$base" >> "$snap/manifest.tsv"
    printf 'svc\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$svc" "$feature" "${fsha:0:10}" "$target" "${tsha:0:10}" "$ahead" "$behind" "$files" "$short" \
      | tee -a "$snap/rollcall.tsv"
    printf 'source\t%s\t%s\torigin/%s@%s\torigin/%s@%s\n' "$svc" "$(slug_for "$svc")" "$feature" "${fsha:0:10}" "$target" "${tsha:0:10}"
    printf 'snapshot\t%s\t%s\t%s\t%s\t%s\n' "$svc" "$rel/$svc-target" "$rel/$svc-feature" "$rel/$svc.diff" "$rel/$svc.files"

    [ "$ahead" = 0 ] && warn "$svc: $feature has no commit $target lacks - nothing to release here"
    [ "$behind" != 0 ] && warn "$svc: $target has $behind commit(s) $feature does not - the diff is from the merge base; comparing the two directories file by file shows those as reverts"
  done <<EOF
$pinned
EOF

  open_prs "$specs"
}

# Open pull requests are context, not the source: the release is the branches.
# But duplicate PRs carrying content already inside the release, with squash
# merge on, land the same content twice under new SHAs - the top blocker of the
# 2026-09-02 release. So for each target, list the open PRs into it: the one
# from the feature branch is `pr`, every other one is `missed`. Without gh this
# is skipped, never fatal.
#
# pr<TAB>service<TAB>num<TAB>review<TAB>merge-state<TAB>title
# missed<TAB>service<TAB>num<TAB>head<TAB>title
open_prs() {
  local svc feature target slug num head review merge title
  if ! command -v gh >/dev/null 2>&1; then
    warn "gh is not installed - open-PR and duplicate-PR checks skipped"; return 0
  fi
  while IFS="$TAB" read -r svc feature target; do
    [ -n "$svc" ] || continue
    slug="$(slug_for "$svc")"
    [ -n "$slug" ] || { warn "$svc: origin is not a GitHub remote - open-PR check skipped"; continue; }
    gh pr list --repo "$slug" --base "$target" --state open --limit 100 \
        --json number,headRefName,reviewDecision,mergeStateStatus,title \
        --jq '.[] | [(.number|tostring), .headRefName, (if (.reviewDecision // "") == "" then "NONE" else .reviewDecision end), (.mergeStateStatus // "?"), .title] | @tsv' \
        < /dev/null > "$WORK/prs" 2>/dev/null \
      || { warn "$svc: gh could not list open PRs into $target - check gh auth"; continue; }
    while IFS="$TAB" read -r num head review merge title; do
      [ -n "$num" ] || continue
      if [ "$head" = "$feature" ]; then
        printf 'pr\t%s\t%s\t%s\t%s\t%s\n' "$svc" "$num" "$review" "$merge" "$title"
      else
        printf 'missed\t%s\t%s\t%s\t%s\n' "$svc" "$num" "$head" "$title"
      fi
    done < "$WORK/prs"
  done <<EOF
$1
EOF
}

# ------------------------------------------------------------------- facts --

# The learned release facts for a checkout alias, or nothing.
learned_release() {
  local f="$LEARNED/$1/qa-release-note.md"
  [ "$1" != "-" ] && [ -f "$f" ] && printf '%s' "$f"
}

# One section of a learned file, heading excluded.
learned_section() {
  awk -v h="## $2" '$0 == h { on = 1; next } /^## / { on = 0 } on' "$1"
}

# Env keys a change adds, and the file that reads each one. Where a key is read
# decides what to do with it: service configuration belongs in the deployment
# config, a one-off tool's key never does. So every file is scanned and the path
# is printed with the key. Covers the common forms: Go os.Getenv / LookupEnv,
# Node process.env.KEY and process.env["KEY"], Python os.environ / os.getenv,
# Ruby ENV["KEY"], and new KEY= lines in any .env.example.
# env<TAB>service<TAB>KEY<TAB>file
facts_env() {
  local slug="$1" diff="$2"
  awk -v slug="$slug" '
    function emit(k) { if (k ~ /^[A-Z][A-Z0-9_]*$/) print "env\t" slug "\t" k "\t" f }
    /^\+\+\+ b\// { f = substr($0, 7); next }
    /^\+/ {
      line = $0
      while (match(line, /(Getenv|LookupEnv|getenv|environ\.get|environ\[|ENV\[|ENV\.fetch\()\(?[ ]*["\x27][A-Z][A-Z0-9_]*["\x27]/)) {
        k = substr(line, RSTART, RLENGTH); sub(/^[^"\x27]*["\x27]/, "", k); sub(/["\x27]$/, "", k)
        emit(k); line = substr(line, RSTART + RLENGTH)
      }
      line = $0
      while (match(line, /process\.env(\.[A-Z][A-Z0-9_]*|\[["\x27][A-Z][A-Z0-9_]*["\x27]\])/)) {
        k = substr(line, RSTART + 11, RLENGTH - 11); gsub(/[^A-Z0-9_]/, "", k)
        emit(k); line = substr(line, RSTART + RLENGTH)
      }
      if (f ~ /\.env\.example$/ && $0 ~ /^\+[A-Z][A-Z0-9_]*=/) {
        k = substr($0, 2); sub(/=.*/, "", k); emit(k)
      }
    }
  ' "$diff" | sort -u
}

# migration<TAB>service<TAB>path
facts_migrations() {
  local slug="$1" diff="$2"
  changed_files "$diff" \
    | grep -E '(^|/)migrations?/.*\.(sql|ts|js|go|py|rb)$' \
    | sed "s|^|migration	$slug	|"
}

# Statements in an added migration that a deploy has to plan around: they lock a
# table, break the old code still serving during a rollout, or change data that
# a code rollback will not put back. Added lines only, case-insensitive, in the
# same files facts_migrations lists - except a down migration, where a DROP is
# the rollback itself rather than a risk. Over-reports on purpose: a comment that
# mentions DROP COLUMN is reported, and the reader drops it.
# ddl<TAB>service<TAB>path<TAB>kind<TAB>statement
facts_ddl() {
  awk -v slug="$1" '
    function emit(kind,   s) {
      s = substr($0, 2); gsub(/\t/, " ", s); gsub(/^ +| +$/, "", s)
      if (length(s) > 140) s = substr(s, 1, 137) "..."
      print "ddl\t" slug "\t" f "\t" kind "\t" s
    }
    /^\+\+\+ b\// {
      f = substr($0, 7)
      mig = (f ~ /(^|\/)migrations?\/.*\.(sql|ts|js|go|py|rb)$/ && f !~ /(\.down\.|_down\.|\/down\/)/)
      next
    }
    mig && /^\+/ {
      l = tolower($0)
      if (l ~ /drop[ \t]+(table|column)/)                emit("drop - irreversible, and breaks code still reading it")
      if (l ~ /rename[ \t]+(column|to)[ \t]/)            emit("rename - breaks the old code still serving during the rollout")
      if (l ~ /alter[ \t]+column.*[ \t]type[ \t]|set[ \t]+data[ \t]+type|modify[ \t]+column/) \
                                                          emit("type change - may rewrite and lock the table")
      if (l ~ /set[ \t]+not[ \t]+null/)                  emit("not null - fails on existing nulls, and scans the table")
      if (l ~ /add[ \t]+column[ \t].*not[ \t]+null/ && l !~ /default/) \
                                                          emit("not null without default - fails on a table that has rows")
      if (l ~ /create[ \t]+(unique[ \t]+)?index/ && l !~ /concurrently/) \
                                                          emit("index without concurrently - may block writes while it builds")
      if (l ~ /add[ \t]+(constraint|foreign[ \t]+key)/ && l !~ /not[ \t]+valid/) \
                                                          emit("constraint - validates the whole table under a lock")
      if (l ~ /(^|[^a-z_])(update[ \t]+[a-z_."`]+[ \t]+set[ \t]|delete[ \t]+from[ \t]|truncate[ \t])/) \
                                                          emit("data change - a code rollback does not undo it")
    }
  ' "$2"
}

# Dependency lines a change adds or removes in a manifest. A - and a + on the same
# name is a bump, and the reader pairs them. Lockfiles are left out - they
# restate the manifest at length - and so are Go's indirect requirements and a
# package.json's own version field.
# dep<TAB>service<TAB>manifest<TAB>+|-<TAB>line
facts_deps() {
  awk -v slug="$1" '
    function emit(   s) {
      s = substr($0, 2); gsub(/\t/, " ", s); gsub(/^ +| +$/, "", s); sub(/,$/, "", s)
      print "dep\t" slug "\t" f "\t" substr($0, 1, 1) "\t" s
    }
    /^\+\+\+ b\// {
      f = substr($0, 7); n = f; sub(/.*\//, "", n); kind = ""
      if (n == "go.mod") kind = "go"
      else if (n == "package.json") kind = "npm"
      else if (n == "pubspec.yaml") kind = "pub"
      else if (n ~ /^requirements.*\.txt$/) kind = "pip"
      else if (n == "pyproject.toml") kind = "pyproject"
      else if (n == "Gemfile") kind = "gem"
      next
    }
    /^--- / || kind == "" || !/^[+-]/ { next }
    kind == "go"  && /^[+-][ \t]*(require[ \t]+)?[a-z0-9.-]+\.[a-z]+\/[^ \t]+[ \t]+v[0-9]/ && !/\/\/ indirect/ { emit(); next }
    kind == "npm" && /^[+-][ \t]*"[@a-z0-9._\/-]+"[ \t]*:[ \t]*"(npm:|workspace:|[~^<>=]*[0-9x*])/ && !/^[+-][ \t]*"version"/ { emit(); next }
    kind == "pub" && /^[+-][ \t]+[a-z0-9_]+:[ \t]*(\^|>=|any|[0-9])/ { emit(); next }
    kind == "pip" && /^[+-][A-Za-z0-9_.-]+(\[[^]]*\])?[ \t]*(==|>=|<=|~=|!=|>|<)/ { emit(); next }
    kind == "pyproject" && /^[+-][ \t]*"?[A-Za-z0-9_.-]+[ \t]*(==|>=|<=|~=|\^|=[ \t]*")/ { emit(); next }
    kind == "gem" && /^[+-][ \t]*gem[ \t]/ { emit(); next }
  ' "$2"
}

# Changes to how a repo is built, shipped or run, rather than to what it does.
# A release that changes its own pipeline is the one most likely to surprise
# whoever presses the button.
# infra<TAB>service<TAB>path
facts_infra() {
  local slug="$1" p
  changed_files "$2" \
    | grep -E '(^|/)(Dockerfile[^/]*|[^/]*\.dockerfile|docker-compose[^/]*\.ya?ml|compose\.ya?ml|Procfile|fly\.toml|app\.ya?ml|serverless\.ya?ml|ecosystem\.config\.[cm]?js|nginx[^/]*\.conf|Makefile|[^/]*\.tf|[^/]*\.tfvars)$|^\.github/workflows/|(^|/)(k8s|kubernetes|helm|charts|deploy|deployments|terraform)/' \
    | while read -r p; do printf 'infra\t%s\t%s\n' "$slug" "$p"; done
}

# A workflow's on: block, at whatever indent the file uses: `trigger<TAB>event`
# for each event, `branch<TAB>pattern` for each on.push.branches entry, in
# either list form. An inline `on: push` or `on: [push, workflow_dispatch]`
# gives its events and no branch filter.
workflow_triggers() {
  awk '
    /^on:/ {
      on = 1; line = $0; sub(/^on:[ \t]*/, "", line); sub(/#.*/, "", line)
      gsub(/[][,]/, " ", line); n = split(line, a, /[ \t]+/)
      for (i = 1; i <= n; i++) if (a[i] != "") print "trigger\t" a[i]
      next
    }
    on && /^[^ #]/                   { exit }
    on && /^[ \t]*(#|$)/             { next }
    on && ind == ""                  { match($0, /^[ ]*/); ind = RLENGTH }
    on {
      match($0, /^[ ]*/)
      if (RLENGTH == ind && $0 ~ /^[ ]*[A-Za-z_]+:/) {
        sec = $0; sub(/^[ ]*/, "", sec); sub(/:.*/, "", sec); print "trigger\t" sec; key = ""
        line = $0; sub(/^[ ]*[A-Za-z_]+:/, "", line)
      } else line = $0
      if (sec != "push") next
      sub(/#.*/, "", line); gsub(/[][,"\x27]/, " ", line)
      n = split(line, a, /[ \t]+/)
      for (i = 1; i <= n; i++) {
        if (a[i] == "" || a[i] == "-") continue
        if (a[i] ~ /:$/) { key = a[i]; continue }
        if (key == "branches:") print "branch\t" a[i]
      }
    }
  ' "$1"
}

# What merging into the target runs, read from every workflow in the feature
# snapshot - the push a merge makes runs the workflows as the feature branch
# left them. One record per workflow a push to <target> triggers, and one per
# deploy-looking workflow that only runs by hand. Which environment a workflow
# reaches is the learned file's to say; this says only what merging sets off.
# deploy<TAB>service<TAB>workflow: triggers<TAB>note
facts_deploy() {
  local svc="$1" target="$2" src="$3" wf ons pushes pat trig hit any=""
  for wf in "$src"/.github/workflows/*.yml "$src"/.github/workflows/*.yaml; do
    [ -f "$wf" ] || continue
    ons="$(workflow_triggers "$wf")"
    pushes="$(printf '%s\n' "$ons" | awk -F'\t' '$1 == "branch" { print $2 }')"
    trig="" hit=""
    if printf '%s\n' "$ons" | grep -qx 'trigger.push'; then
      if [ -n "$pushes" ]; then
        trig="push($(printf '%s' "$pushes" | tr '\n' ',' | sed 's/,$//'))"
        while read -r pat; do
          [ -n "$pat" ] || continue
          # shellcheck disable=SC2254 - the pattern is the point
          case "$target" in $pat) hit=yes; break ;; esac
        done <<EOF
$pushes
EOF
      else
        # No branch filter: it fires on every branch, the target too.
        trig="push(any branch)"; hit=yes
      fi
    fi
    printf '%s\n' "$ons" | grep -qx 'trigger.workflow_dispatch' && trig="${trig:+$trig + }manual"
    printf '%s\n' "$ons" | grep -qx 'trigger.schedule' && trig="${trig:+$trig + }schedule"

    if [ -n "$hit" ]; then
      printf 'deploy\t%s\t%s: %s\tmerging into %s runs this workflow - the learned dev-deployment-note file says which environment it reaches\n' \
        "$svc" "$(basename "$wf")" "$trig" "$target"
      any=yes
    elif case "$trig" in *manual*) true ;; *) false ;; esac; then
      case "$(basename "$wf")" in
        *deploy*|*cd*|*release*|*prod*)
          printf 'deploy\t%s\t%s: %s\tmanual trigger - merging into %s does not run it\n' "$svc" "$(basename "$wf")" "$trig" "$target" ;;
      esac
    fi
  done
  [ -n "$any" ] || printf 'deploy\t%s\tnone\tno workflow runs on a push to %s - merging deploys nothing by itself; the learned file or the repo says how it ships, confirm it by hand\n' "$svc" "$target"
}

# Contracts copied between repos rather than shared - protos, schemas - drift,
# and a change in one is silently a release task in every repo holding a copy.
# A copy is a file of the same name anywhere in another checkout's default
# branch.
# proto<TAB>service<TAB>path<TAB>other repos carrying a copy
facts_proto() {
  local slug="$1" diff="$2" p base d others other al="$1" ref
  changed_files "$diff" | grep -E '\.(proto|avsc|thrift)$' | while read -r p; do
    base="$(basename "$p")"
    others=""
    for d in "$ROOT"/repos/*/; do
      [ -e "$d/.git" ] || continue
      other="$(basename "$d")"
      [ "$other" = "$al" ] && continue
      ref="$(canonical_ref "$other")"
      git -C "$d" ls-tree -r --name-only "$ref" 2>/dev/null | grep -qE "(^|/)$base\$" || continue
      others="$others $other"
    done
    others="${others# }"
    printf 'proto\t%s\t%s\t%s\n' "$slug" "$p" "${others:-no other repo carries a copy}"
  done
}

# The app whose learned file names a route registry: "<alias><TAB><file><TAB><host form>".
# At most one - an app routes links, services emit them.
deeplink_registry() {
  local f al file host
  for f in "$LEARNED"/*/qa-release-note.md; do
    [ -f "$f" ] || continue
    al="$(basename "$(dirname "$f")")"
    file="$(learned_section "$f" "Deeplink registry" | sed -n 's/^- file: `\([^`]*\)`.*/\1/p' | head -1)"
    host="$(learned_section "$f" "Deeplink registry" | sed -n 's/^- host: `\([^`]*\)`.*/\1/p' | head -1)"
    [ -n "$file" ] && [ -n "$host" ] || continue
    printf '%s\t%s\t%s\n' "$al" "$file" "$host"
    return 0
  done
  return 1
}

# Any deeplink a change emits, checked against the app's own registry of hosts.
# The scheme is usually configurable per environment, and fixtures use several,
# so the scheme says nothing: the HOST is what the app routes on, so that is
# what is checked. A third-party scheme is reported the same way - the app never
# routes it, and the reader tells the two apart.
# deeplink<TAB>service<TAB>scheme://host<TAB>routable|NOT-IN-THE-APPS-REGISTRY|no registry
facts_deeplink() {
  local slug="$1" diff="$2" reg="" app file form link host pat
  if app="$(deeplink_registry)"; then
    file="$(printf '%s' "$app" | cut -f2)"; form="$(printf '%s' "$app" | cut -f3)"
    reg="$(repo_path "$(printf '%s' "$app" | cut -f1)" "$file")"
  fi
  # A deeplink is a custom scheme. Ordinary web URLs in a diff are noise, so
  # http/https and the other standard schemes are excluded rather than matched.
  grep -E '^\+' "$diff" \
    | grep -oE '[a-z][a-z0-9.+-]*://[a-z0-9_-]+' \
    | grep -vE '^(https?|ftps?|mailto|wss?|file|data|git|ssh|postgres(ql)?|mysql|mongodb(\+srv)?|redis|amqps?|s3|gs)://' \
    | sort -u | while read -r link; do
      [ -n "$link" ] || continue
      host="${link##*://}"
      if [ -z "$reg" ] || [ ! -f "$reg" ]; then
        printf 'deeplink\t%s\t%s\tno registry learned - /learn qa-release-note <app repo> to check routes\n' "$slug" "$link"
        continue
      fi
      pat="${form//\{host\}/$host}"
      if grep -qF -- "$pat" "$reg" 2>/dev/null; then
        printf 'deeplink\t%s\t%s\troutable - the app has a route for "%s"\n' "$slug" "$link" "$host"
      else
        printf 'deeplink\t%s\t%s\tNOT-IN-THE-APPS-REGISTRY - another app'"'"'s link, or one nothing routes\n' "$slug" "$link"
      fi
    done
}

# Who each changed file faces, from the repo's learned `## Surfaces` globs.
# First matching glob wins. A repo with no learned file gets one `learn`
# record instead - the audience is never guessed from a folder name.
# surface<TAB>service<TAB>path<TAB>audience-or-channel
# learn<TAB>service<TAB>what is missing
facts_surface() {
  local slug="$1" diff="$2" al="$1" f rules p glob label hit
  if ! f="$(learned_release "$al")"; then
    printf 'learn\t%s\tno surfaces learned for this repo - /learn qa-release-note %s, or read the audience off each handler\n' "$slug" "$al"
    return
  fi
  rules="$(learned_section "$f" Surfaces | sed -n 's/^- `\([^`]*\)` -> \(.*\)$/\1\t\2/p')"
  [ -n "$rules" ] || return 0
  changed_files "$diff" | while read -r p; do
    hit=""
    while IFS="$(printf '\t')" read -r glob label; do
      [ -n "$glob" ] || continue
      # shellcheck disable=SC2254 - the glob is the point
      case "$p" in $glob) hit="$label"; break ;; esac
    done <<EOF
$rules
EOF
    [ -n "$hit" ] && printf 'surface\t%s\t%s\t%s\n' "$slug" "$p" "$hit"
  done
}

# ---------------------------------------------------------------- extract --

# The team already writes the QA section, inside test names - it just never
# leaves the repo. The forms, all required:
#
#   1  ±func Test…            a removed/added pair IS the behaviour change (Go)
#   2  t.Run("…")             already plain English, lifted verbatim (Go)
#   3  name: "…"              table case, labelled
#   4  {"…", …}               table case, POSITIONAL - once missed, and it
#                             produced a false "no test coverage" report on a
#                             wording change. Not optional.
#   5  it/test/describe("…")  Jest, Vitest, Mocha - plain English already
#   6  def test_…             pytest, split into words like Go's names
#
# test<TAB>service<TAB>+|-<TAB>func|case<TAB>text
extract_tests() {
  local slug="$1" diff="$2"

  # 1. top-level test functions, camelCase and _ split into words
  grep -E '^[+-]func Test' "$diff" \
    | sed -E -e 's/\(.*//' -e 's/^([+-])func Test/\1/' \
    | sed -E -e 's/_/ /g' -e 's/([a-z0-9])([A-Z])/\1 \2/g' \
             -e 's/([A-Z])([A-Z][a-z])/\1 \2/g' \
    | awk -v slug="$slug" '{ s=substr($0,1,1); t=substr($0,2); sub(/^ +/,"",t);
                             print "test\t" slug "\t" s "\tfunc\t" tolower(t) }'

  # 2 & 3. t.Run("…") and name: "…"
  grep -E '^[+-].*(t\.Run\(|name:)[[:space:]]*"' "$diff" \
    | sed -E 's/^([+-]).*(t\.Run\(|name:)[[:space:]]*"([^"]*)".*/\1\t\3/' \
    | awk -F'\t' -v slug="$slug" 'NF==2 && $2 != "" { print "test\t" slug "\t" $1 "\tcase\t" $2 }'

  # 4. positional table entries: {"a settled payment", …}. The comma after the
  #    closing quote is what separates a struct field from a map key.
  grep -E '^[+-][[:space:]]*\{"[^"]+"[[:space:]]*,' "$diff" \
    | sed -E 's/^([+-])[[:space:]]*\{"([^"]*)".*/\1\t\2/' \
    | awk -F'\t' -v slug="$slug" 'NF==2 && $2 != "" { print "test\t" slug "\t" $1 "\tcase\t" $2 }'

  # 5. it("…") / test("…") / describe("…"), any quote style, .only/.skip/.each included
  grep -E "^[+-][[:space:]]*(it|test|describe)(\.[a-z]+)?(\([^)]*\))?\([[:space:]]*['\"\`]" "$diff" \
    | sed -E "s/^([+-])[[:space:]]*(it|test|describe)(\.[a-z]+)?(\([^)]*\))?\([[:space:]]*['\"\`]([^'\"\`]*)['\"\`].*/\1\t\5/" \
    | awk -F'\t' -v slug="$slug" 'NF==2 && $2 != "" { print "test\t" slug "\t" $1 "\tcase\t" $2 }'

  # 6. pytest functions
  grep -E '^[+-][[:space:]]*(async[[:space:]]+)?def test_' "$diff" \
    | sed -E 's/^([+-])[[:space:]]*(async[[:space:]]+)?def test_([A-Za-z0-9_]*).*/\1\t\3/' \
    | awk -F'\t' -v slug="$slug" 'NF==2 && $2 != "" { gsub(/_/, " ", $2); print "test\t" slug "\t" $1 "\tfunc\t" $2 }'
}

# A user-visible change with no test assertion is a release risk. The first run
# of this found two in a single PR - a narrowed discount rule and a new admin
# filter - neither of which had a test.
# gap<TAB>service<TAB>path
extract_gaps() {
  local slug="$1" diff="$2" tmp
  tmp="$WORK/gaps.$$"
  changed_files "$diff" > "$tmp.all"
  grep -E '(_test\.go|_test\.dart|\.test\.[jt]sx?|\.spec\.[jt]sx?|(^|/)test_[^/]*\.py|_test\.py|_spec\.rb)$' "$tmp.all" \
    | sed 's|/[^/]*$||' | sort -u > "$tmp.tested"

  grep -E '\.(go|ts|tsx|js|jsx|dart|py|rb|kt|java)$' "$tmp.all" \
    | grep -vE '(_test\.go|_test\.dart|\.test\.[jt]sx?|\.spec\.[jt]sx?|(^|/)test_[^/]*\.py|_test\.py|_spec\.rb)$' \
    | grep -vE '(^|/)(vendor|node_modules|dist|mocks?|docs)/' \
    | grep -vE '(\.pb\.go|_mock\.go|\.gen\.go)$' \
    | while read -r p; do
        grep -qxF "$(dirname "$p")" "$tmp.tested" || printf 'gap\t%s\t%s\n' "$slug" "$p"
      done
  rm -f "$tmp.all" "$tmp.tested"
}

changed_files() { grep -E '^\+\+\+ b/' "$1" | sed 's|^+++ b/||' | grep -v '^/dev/null$' | sort -u; }

# ------------------------------------------------------------------ report --

# Everything this script can say about one diff.
local_facts() {
  facts_env        "$1" "$2"
  facts_migrations "$1" "$2"
  facts_ddl        "$1" "$2"
  facts_deps       "$1" "$2"
  facts_infra      "$1" "$2"
  facts_proto      "$1" "$2"
  facts_deeplink   "$1" "$2"
  facts_surface    "$1" "$2"
  extract_tests    "$1" "$2"
  extract_gaps     "$1" "$2"
}

# moved<TAB>service<TAB>origin/branch<TAB>snapshot sha<TAB>sha on origin now
stale_check() {
  local now
  now="$(remote_sha "$1" "$2")"
  if [ -z "$now" ]; then
    warn "$1: could not ask origin about $2 - the snapshot may be stale"
  elif [ "$now" != "$3" ]; then
    printf 'moved\t%s\torigin/%s\t%s\t%s\n' "$1" "$2" "${3:0:10}" "${now:0:10}"
  fi
}

# Facts from the snapshot `prepare` left, never from a fresh fetch: the notes
# describe the commits in manifest.tsv, and the directories beside it are what
# the reader opens to check them.
report() {
  local snap="$1" svc feature fsha target tsha base diff
  kv taken "$(cat "$snap/taken" 2>/dev/null)"
  cat "$snap/rollcall.tsv"

  # The snapshot is what the notes describe, so it is not refetched - but ask
  # origin whether either branch has moved since, so stale notes say so.
  while IFS="$TAB" read -r svc feature fsha target tsha base; do
    [ -n "$svc" ] || continue
    stale_check "$svc" "$feature" "$fsha"
    stale_check "$svc" "$target" "$tsha"
  done < "$snap/manifest.tsv"

  while IFS="$TAB" read -r svc feature fsha target tsha base; do
    [ -n "$svc" ] || continue
    diff="$snap/$svc.diff"
    if [ ! -s "$diff" ]; then
      warn "$svc: empty diff - $feature brings nothing $target lacks"
      continue
    fi
    kv diff-lines "$svc	$(wc -l < "$diff" | tr -d ' ')"
    local_facts "$svc" "$diff"
    facts_deploy "$svc" "$target" "$snap/$svc-feature"
  done < "$snap/manifest.tsv"
}

# ------------------------------------------------------------------- page --

# The page's name: the notes' first heading, without the dash it carries
# ("gsa — Deployment Notes" -> "gsa Deployment Notes").
page_title() {
  sed -n 's/^# //p' "$1" | head -1 | sed -e 's/ *[—–-]\{1,2\} */ /g' -e 's/  */ /g' \
    | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# The notes as one self-contained page. The markdown is embedded verbatim and
# rendered in the viewer's browser, so the page always says exactly what the
# notes file says - there is no second copy to drift. Only `</script` and `<!--`
# are escaped, the two sequences that could end or confuse the embedding block;
# the page puts them back before rendering. If the renderer cannot load, the
# raw notes are shown instead, so the page is never empty.
build_page() {
  local md="$1" out="$2" title
  [ -f "$md" ] || return 1
  title="$(page_title "$md")"
  {
    printf '<title>%s</title>\n' "${title:-Deployment Notes}"
    cat <<'HTML'
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&family=IBM+Plex+Sans:ital,wght@0,400;0,500;0,600;0,700;1,400&display=swap">
<style>
/* A runbook: a quiet contents rail beside one readable column; tables and
   code scroll inside their own frames. */
:root {
  --paper: #f5f7f8; --surface: #ffffff; --ink: #17212b; --muted: #5a6672;
  --rule: #d8dee3; --code: #edf1f3; --accent: #0d6b70; --accent-soft: #dcefef;
  --go: #1d7a40; --go-soft: #e2f3e8; --warn: #9a5800; --warn-soft: #fbefdc;
  --stop: #b3261e; --stop-soft: #fbe5e3;
  --sans: "IBM Plex Sans", system-ui, -apple-system, "Segoe UI", sans-serif;
  --mono: "IBM Plex Mono", ui-monospace, "SFMono-Regular", Menlo, Consolas, monospace;
}
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) {
  --paper: #0f1519; --surface: #151d23; --ink: #e3e9ee; --muted: #9aa6b1;
  --rule: #27333c; --code: #121a20; --accent: #5cbcbe; --accent-soft: #163236;
  --go: #6fcf8f; --go-soft: #15301f; --warn: #f0b860; --warn-soft: #33270f;
  --stop: #f38b82; --stop-soft: #3a1a18; color-scheme: dark;
} }
:root[data-theme="dark"] {
  --paper: #0f1519; --surface: #151d23; --ink: #e3e9ee; --muted: #9aa6b1;
  --rule: #27333c; --code: #121a20; --accent: #5cbcbe; --accent-soft: #163236;
  --go: #6fcf8f; --go-soft: #15301f; --warn: #f0b860; --warn-soft: #33270f;
  --stop: #f38b82; --stop-soft: #3a1a18; color-scheme: dark;
}
* { box-sizing: border-box; }
body { background: var(--paper); color: var(--ink); font: 15px/1.6 var(--sans); }
.shell { display: grid; grid-template-columns: minmax(0, 1fr); gap: 32px;
  max-width: 1180px; margin: 0 auto; padding-inline: 16px; padding-block: 24px 64px; }
@media (min-width: 1000px) { .shell { grid-template-columns: 230px minmax(0, 1fr); padding-inline: 32px; } }
nav.toc { font-size: 13px; }
@media (min-width: 1000px) { nav.toc { position: sticky; top: calc(env(safe-area-inset-top, 0px) + 24px);
  align-self: start; max-height: calc(100vh - 48px); overflow: auto; } }
nav.toc details { border: 1px solid var(--rule); border-radius: 8px; background: var(--surface); padding: 10px 14px; }
@media (min-width: 1000px) { nav.toc details { border: 0; background: none; padding: 0; } nav.toc summary { display: none; } }
nav.toc summary { cursor: pointer; font-weight: 600; }
nav.toc .label { text-transform: uppercase; letter-spacing: .08em; font-size: 11px; color: var(--muted); margin: 0 0 8px; }
nav.toc ol { list-style: none; margin: 0; padding: 0; display: grid; gap: 2px; }
nav.toc a { display: block; color: var(--muted); text-decoration: none; padding: 4px 8px; border-radius: 6px; }
nav.toc a:hover, nav.toc a:focus-visible { color: var(--ink); background: var(--accent-soft); outline: none; }
main { min-width: 0; max-width: 860px; }
main h1 { font-size: 30px; line-height: 1.2; margin: 0 0 12px; text-wrap: balance; letter-spacing: -.01em; }
main h2 { font-size: 21px; margin: 44px 0 12px; padding-top: 18px; border-top: 1px solid var(--rule); text-wrap: balance; scroll-margin-top: 16px; }
main h3 { font-size: 16.5px; margin: 28px 0 8px; scroll-margin-top: 16px; }
main p, main li { max-width: 72ch; }
main a { color: var(--accent); }
main ul, main ol { padding-left: 1.3em; }
main li + li { margin-top: 3px; }
main hr { display: none; }
main blockquote { margin: 16px 0; padding: 10px 16px; border-left: 3px solid var(--accent); background: var(--accent-soft); border-radius: 0 6px 6px 0; }
main code { font: 0.88em var(--mono); background: var(--code); padding: 1px 5px; border-radius: 4px; }
.table-wrap { overflow-x: auto; margin: 14px 0; border: 1px solid var(--rule); border-radius: 8px; background: var(--surface); }
table { border-collapse: collapse; width: 100%; font-size: 13.5px; font-variant-numeric: tabular-nums; }
th, td { text-align: left; vertical-align: top; padding: 8px 12px; border-bottom: 1px solid var(--rule); }
th { font-weight: 600; background: var(--code); white-space: nowrap; }
tr:last-child td { border-bottom: 0; }
figure.code { position: relative; margin: 16px 0; }
figure.code pre { margin: 0; overflow-x: auto; padding: 16px; background: var(--code); border: 1px solid var(--rule);
  border-radius: 8px; font: 13px/1.55 var(--mono); }
figure.code pre code { background: none; padding: 0; font-size: inherit; }
figure.code button { position: absolute; top: 8px; right: 8px; font: 500 12px var(--sans); color: var(--ink);
  background: var(--surface); border: 1px solid var(--rule); border-radius: 6px; padding: 4px 10px; cursor: pointer; }
figure.code button:hover, figure.code button:focus-visible { border-color: var(--accent); outline: none; }
.verdict { padding: 12px 16px; border-radius: 8px; border: 1px solid var(--rule); background: var(--surface); }
.verdict.go { background: var(--go-soft); border-color: var(--go); }
.verdict.cond { background: var(--warn-soft); border-color: var(--warn); }
.verdict.stop { background: var(--stop-soft); border-color: var(--stop); }
input[type="checkbox"] { accent-color: var(--accent); }
.raw { white-space: pre-wrap; font: 13px/1.55 var(--mono); }
@media (prefers-reduced-motion: no-preference) { html { scroll-behavior: smooth; } }
</style>
<div class="shell">
  <nav class="toc" aria-label="Contents">
    <details id="toc-box" open><summary>Contents</summary>
      <p class="label">Contents</p>
      <ol id="toc-list"></ol>
    </details>
  </nav>
  <main id="notes"></main>
</div>
<script type="text/markdown" id="notes-md">
HTML
    perl -pe 's#</(script)#<\\/$1#gi; s#<!--#<\\!--#g' "$md"
    cat <<'HTML'
</script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/marked/12.0.2/marked.min.js"></script>
<script>
(function () {
  var src = document.getElementById("notes-md").textContent
    .replace(/<\\\/(script)/gi, "</$1").replace(/<\\!--/g, "<!--").replace(/^\n/, "");
  var main = document.getElementById("notes");
  if (!window.marked) {
    var raw = document.createElement("pre");
    raw.className = "raw"; raw.textContent = src; main.appendChild(raw);
    document.querySelector("nav.toc").hidden = true;
    return;
  }
  main.innerHTML = window.marked.parse(src, { gfm: true });

  main.querySelectorAll("table").forEach(function (t) {
    var wrap = document.createElement("div"); wrap.className = "table-wrap";
    t.parentNode.insertBefore(wrap, t); wrap.appendChild(t);
  });

  main.querySelectorAll("pre").forEach(function (pre) {
    var fig = document.createElement("figure"); fig.className = "code";
    pre.parentNode.insertBefore(fig, pre); fig.appendChild(pre);
    var btn = document.createElement("button"); btn.type = "button"; btn.textContent = "Copy";
    btn.addEventListener("click", function () {
      var text = pre.innerText;
      var done = function () { btn.textContent = "Copied"; setTimeout(function () { btn.textContent = "Copy"; }, 1600); };
      var select = function () { var r = document.createRange(); r.selectNodeContents(pre);
        var s = window.getSelection(); s.removeAllRanges(); s.addRange(r); btn.textContent = "Selected"; };
      try { navigator.clipboard.writeText(text).then(done, select); } catch (e) { select(); }
    });
    fig.appendChild(btn);
  });

  var used = {}, toc = document.getElementById("toc-list");
  main.querySelectorAll("h2, h3").forEach(function (h) {
    var base = h.textContent.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "section";
    var id = base, n = 2; while (used[id]) { id = base + "-" + n++; } used[id] = true; h.id = id;
    if (h.tagName === "H2") {
      var li = document.createElement("li"), a = document.createElement("a");
      a.href = "#" + id; a.textContent = h.textContent;
      li.appendChild(a); toc.appendChild(li);
    }
    if (h.tagName === "H3" && /^verdict/i.test(h.textContent)) {
      var t = h.textContent;
      h.classList.add("verdict", /NO-GO|🔴/.test(t) ? "stop" : /CONDITION|🟠|🟡/.test(t) ? "cond" : "go");
    }
  });
  if (!toc.children.length) document.querySelector("nav.toc").hidden = true;
  try { if (window.matchMedia("(max-width: 999px)").matches) document.getElementById("toc-box").open = false; } catch (e) {}
  if (location.hash) { var target = document.getElementById(location.hash.slice(1)); if (target) target.scrollIntoView(); }
})();
</script>
HTML
  } > "$out"
}

# ------------------------------------------------------------------- shell --

header() {
  local name="$1" day="$2" prev
  kv mode "$MODE"
  kv release "$name"
  kv date "$day"
  kv outfile "release/$day-$name/$day-$name.md"
  prev="$(previous_notes "$day-$name")"
  [ -n "$prev" ] && kv prev "${prev#$ROOT/}"
  kv note "every SHA is the one origin reports for the branch, never a local branch or stale ref; open PRs are context only"
}

# The newest notes other than <date>-<name>'s own, by date. Notes live in their
# release directory now; older ones sit loose in release/.
previous_notes() {
  local f
  {
    for f in "$RELEASE_DIR"/*.md; do
      [ -f "$f" ] && [ "$(basename "$f")" != README.md ] && printf '%s\n' "$f"
    done
    for f in "$RELEASE_DIR"/*/*.md; do
      [ -f "$f" ] && [ "$(basename "$f" .md)" = "$(basename "$(dirname "$f")")" ] && printf '%s\n' "$f"
    done
  } | grep -vF "/$1.md" | awk -F/ '{ print $NF "\t" $0 }' | sort | tail -1 | cut -f2
}

check_name() {
  if [ -z "$1" ]; then
    printf 'error\tname required: deployment-notes.sh %s <name> ...\n' "$MODE"; exit 2
  fi
  # Lower-case, digits, dash and dot. Dots because release names are versions
  # as often as words - the runbooks on disk are 2026-09-02-5.1.md. What is
  # refused is anything that would not survive being a filename: spaces,
  # slashes, and a leading dot.
  case "$1" in
    .*|*[!a-z0-9.-]*) printf 'error\tname must be lower-case letters, digits, - and . : %s\n' "$1"; exit 2 ;;
  esac
}

MODE="${1:-}"
[ $# -gt 0 ] && shift

case "$MODE" in
  prepare)
    NAME="${1:-}"; check_name "$NAME"; shift
    header "$NAME" "$TODAY"
    if [ $# -eq 0 ]; then
      warn "no service lines given - one per line: <service> -> <feature> -> <target>"
      exit 0
    fi
    WORK="$(mktemp -d "${TMPDIR:-/tmp}/deployment-notes.XXXXXX")"
    prepare "$NAME" "$@" || exit 2
    date '+%Y-%m-%d %H:%M %Z' > "$(snapshot_today "$NAME")/taken"
    ;;
  report)
    NAME="${1:-}"; check_name "$NAME"
    SNAP="$(snapshot_latest "$NAME")" || { printf 'error\tno snapshot for %s - run prepare first\n' "$NAME"; exit 2; }
    DAY="$(basename "$SNAP")"; DAY="${DAY:0:10}"
    header "$NAME" "$DAY"
    kv snapshot-dir "${SNAP#$ROOT/}"
    WORK="$(mktemp -d "${TMPDIR:-/tmp}/deployment-notes.XXXXXX")"
    report "$SNAP"
    ;;
  facts)
    [ $# -eq 2 ] && [ -f "$2" ] || { printf 'error\tusage: deployment-notes.sh facts <service> <diff-file>\n'; exit 2; }
    WORK="$(mktemp -d "${TMPDIR:-/tmp}/deployment-notes.XXXXXX")"
    local_facts "$1" "$2"
    ;;
  clean)
    NAME="${1:-}"; check_name "$NAME"
    # Only directories this script made - the manifest marks them. The notes,
    # the page and the artifact link inside are kept; an emptied directory goes.
    found=0
    for d in "$RELEASE_DIR"/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-"$NAME"/; do
      [ -f "$d/manifest.tsv" ] || continue
      snapshot_wipe "${d%/}"
      rmdir "${d%/}" 2>/dev/null && kv removed "release/$(basename "$d")" \
        || kv cleaned "release/$(basename "$d") - notes kept"
      found=1
    done
    [ "$found" -eq 1 ] || warn "no snapshot for $NAME"
    ;;
  page)
    NAME="${1:-}"; check_name "$NAME"
    DIR="$(notes_dir_latest "$NAME")" || { printf 'error\tno notes for %s - write release/<date>-%s/<date>-%s.md first\n' "$NAME" "$NAME" "$NAME"; exit 2; }
    BASE="$(basename "$DIR")"
    build_page "$DIR/$BASE.md" "$DIR/$BASE.html" || { printf 'error\tcould not build the page\n'; exit 2; }
    kv page "${DIR#$ROOT/}/$BASE.html"
    kv title "$(page_title "$DIR/$BASE.md")"
    if [ -s "$DIR/artifact.url" ]; then
      kv artifact-url "$(head -1 "$DIR/artifact.url")"
    else
      kv artifact-url -
    fi
    ;;
  slash)
    exec "${BASH_SOURCE[0]}" prepare "$@"
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    printf 'error\tunknown mode: %s\n' "$MODE"
    usage
    exit 2
    ;;
esac
