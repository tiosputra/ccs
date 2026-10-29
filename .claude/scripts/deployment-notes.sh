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

# What the operations team will feel: a sheet the code now writes or reads, a
# WhatsApp, email, push or chat message it sends, a job it schedules. Matched on
# added lines and on the changed path, once per kind per file, tests and
# lockfiles skipped. Over-reports on purpose - the ops-release-note skill judges
# each one. The excerpt is the first matching line, trimmed; never copy a value
# out of it into the notes.
# ops<TAB>service<TAB>sheet|whatsapp|email|push|chat|schedule<TAB>path<TAB>excerpt
facts_ops() {
  local slug="$1" diff="$2"
  awk -v slug="$slug" '
    function kinds(s,   l, k) {
      l = tolower(s); k = ""
      if (l ~ /spreadsheet|gsheet|google[ _.-]?sheet|sheets\.googleapis|sheet_?id|sheetname|sheet_name/) k = k " sheet"
      if (l ~ /whatsapp|wa\.me\//)                                                   k = k " whatsapp"
      if (l ~ /sendgrid|mailgun|mailjet|smtp|nodemailer|sendmail|send_?email|email_?template|mailer|\.mjml/) k = k " email"
      if (l ~ /fcm|firebase[ _.-]?messaging|onesignal|push_?notif|sendpush|send_push/) k = k " push"
      if (l ~ /slack|telegram|discord/)                                              k = k " chat"
      if (l ~ /cron|@every|schedule(r|d)?[(.]/)                                     k = k " schedule"
      return k
    }
    function emit(s,   ks, n, i, x) {
      ks = kinds(s); n = split(ks, x, " ")
      for (i = 1; i <= n; i++) {
        if (seen[x[i] SUBSEP f]++) continue
        ex = substr(s, 2); gsub(/\t/, " ", ex); sub(/^[ ]+/, "", ex)
        print "ops\t" slug "\t" x[i] "\t" f "\t" substr(ex, 1, 120)
      }
    }
    /^\+\+\+ b\// {
      f = substr($0, 7)
      skip = (f ~ /(_test\.go|_test\.dart|\.test\.[jt]sx?|\.spec\.[jt]sx?|_test\.py|_spec\.rb|lock\.json|\.lock|go\.sum|pubspec\.lock)$/)
      if (!skip) emit("+" f)
      next
    }
    /^\+/ && !skip { emit($0) }
  ' "$diff"
}

# Who wrote the release: commit authors between the merge base and the feature
# SHA in manifest.tsv, merges and bots left out. Read from the checkout's object
# store, which holds exactly those commits since prepare fetched them - the SHAs
# are pinned, so no branch or working tree is consulted.
# people<TAB>service<TAB>name<TAB>emails, comma-separated<TAB>commits
facts_people() {
  local svc="$1" base="$2" fsha="$3" log
  if ! log="$(git -C "$ROOT/repos/$svc" log --no-merges --format='%aN%x09%aE' "$base..$fsha" 2>/dev/null)"; then
    warn "$svc: could not read the commits between the merge base and the feature - participants unknown"
    return
  fi
  printf '%s\n' "$log" \
    | awk -F'\t' 'NF == 2 && tolower($0) !~ /\[bot\]|dependabot|github-actions|renovate/' \
    | awk -F'\t' -v svc="$svc" '
        { n[$1]++; if (index("," e[$1] ",", "," $2 ",") == 0) e[$1] = (e[$1] == "" ? $2 : e[$1] "," $2) }
        END { for (a in n) print "people\t" svc "\t" a "\t" e[a] "\t" n[a] }' \
    | sort -t"$TAB" -k5,5nr
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
  facts_ops        "$1" "$2"
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
    facts_people "$svc" "$base" "$fsha"
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
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Public+Sans:ital,wght@0,400;0,500;0,600;0,700;1,400&family=Source+Serif+4:opsz,wght@8..60,600;8..60,700&family=JetBrains+Mono:wght@400;500&display=swap">
<style>
/* Layout: an admin-panel shell - a fixed white sidebar with the release, its
   verdict and a folding contents tree; the notes read in the middle as one
   white page on a soft blue-grey desk. Light by request: one theme, set
   explicitly, so it reads the same on any host. */
:root {
  color-scheme: light;
  --desk: #eef2f6;        /* the page behind the sheet */
  --sheet: #ffffff;       /* the article and the sidebar */
  --ink: #1b2430;         /* running text */
  --muted: #5d6b7b;       /* captions, inactive links */
  --line: #dde3ea;        /* hairlines and borders */
  --wash: #f5f7fa;        /* table heads, code, zebra rows */
  --accent: #1d5fa6;      /* links, active section */
  --accent-wash: #e8f0fa;
  --go: #1c7a43; --go-wash: #e5f4eb;
  --warn: #8f5a00; --warn-wash: #fdf3df;
  --stop: #b42318; --stop-wash: #fdecea;
  --display: "Source Serif 4", Georgia, "Times New Roman", serif;
  --sans: "Public Sans", system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
  --mono: "JetBrains Mono", ui-monospace, "SFMono-Regular", Menlo, Consolas, monospace;
  --side: 288px;
}
* { box-sizing: border-box; }
body { background: var(--desk); color: var(--ink); font: 16px/1.7 var(--sans); }
body::before { content: ""; position: fixed; inset: 0 0 auto; height: env(safe-area-inset-top, 0px); z-index: 30; background: var(--sheet); }

/* ---- sidebar ---- */
.side { position: fixed; z-index: 20; top: 0; bottom: 0; left: 0; width: var(--side);
  display: flex; flex-direction: column; background: var(--sheet); border-right: 1px solid var(--line);
  padding-top: env(safe-area-inset-top, 0px); padding-left: env(safe-area-inset-left, 0px); }
.brand { padding: 22px 22px 18px; border-bottom: 1px solid var(--line); display: grid; gap: 6px; }
.eyebrow { font: 600 11px/1.3 var(--sans); letter-spacing: .1em; text-transform: uppercase; color: var(--muted); }
.brand .name { font: 700 20px/1.25 var(--display); color: var(--ink); text-wrap: balance; overflow-wrap: anywhere; }
.brand .meta { display: flex; flex-wrap: wrap; gap: 6px 8px; align-items: center; font-size: 12.5px; color: var(--muted); }
.pill { display: inline-flex; align-items: center; gap: 6px; font: 600 11.5px/1 var(--sans); letter-spacing: .02em;
  padding: 5px 9px; border-radius: 999px; border: 1px solid currentColor; white-space: nowrap; }
.pill::before { content: ""; width: 7px; height: 7px; border-radius: 50%; background: currentColor; }
.pill.go { color: var(--go); background: var(--go-wash); }
.pill.cond { color: var(--warn); background: var(--warn-wash); }
.pill.stop { color: var(--stop); background: var(--stop-wash); }
.toc { flex: 1; overflow-y: auto; padding: 14px 12px 28px; font-size: 14px; }
.toc ol { list-style: none; margin: 0; padding: 0; display: grid; gap: 1px; }
.toc a { display: block; color: var(--muted); text-decoration: none; padding: 6px 10px; border-radius: 6px; line-height: 1.35; }
.toc a:hover { color: var(--ink); background: var(--wash); }
.toc a:focus-visible, .toc button:focus-visible, .menu:focus-visible { outline: 2px solid var(--accent); outline-offset: 1px; }
.toc .row { display: flex; align-items: center; gap: 2px; }
.toc .row a { flex: 1; min-width: 0; font-weight: 600; color: var(--ink); }
.toc .row a:first-child { margin-left: 26px; }
.toc button.fold { flex: none; width: 24px; height: 24px; padding: 0; border: 0; border-radius: 5px; background: none;
  color: var(--muted); cursor: pointer; display: grid; place-items: center; }
.toc button.fold svg { width: 12px; height: 12px; transition: transform .15s ease; }
.toc button.fold:hover { background: var(--wash); color: var(--ink); }
.toc li.open > .row button.fold svg { transform: rotate(90deg); }
.toc ol.subs { display: none; margin: 2px 0 8px 22px; padding-left: 10px; border-left: 1px solid var(--line); }
.toc li.open > ol.subs { display: grid; }
.toc li.sub a { font-size: 13.5px; padding: 5px 10px; }
.toc li.sub a .n { font: 500 12px var(--mono); color: var(--muted); margin-right: 6px; }
.toc a.active { color: var(--accent); background: var(--accent-wash); }
.toc a.active .n { color: var(--accent); }

/* ---- content ---- */
.content { margin-left: var(--side); min-width: 0; }
.bar { position: sticky; top: env(safe-area-inset-top, 0px); z-index: 10; display: flex; align-items: center; gap: 12px;
  min-height: 52px; background: rgba(255, 255, 255, .92); backdrop-filter: blur(6px); border-bottom: 1px solid var(--line);
  padding-left: max(24px, env(safe-area-inset-left, 0px)); padding-right: max(24px, env(safe-area-inset-right, 0px)); }
.crumb { min-width: 0; font-size: 13.5px; color: var(--muted); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.crumb b { color: var(--ink); font-weight: 600; }
.menu { display: none; flex: none; align-items: center; gap: 8px; font: 600 13.5px var(--sans); color: var(--ink);
  background: var(--sheet); border: 1px solid var(--line); border-radius: 8px; padding: 7px 12px; cursor: pointer; }
.desk { padding-block: 32px 80px; padding-left: max(24px, env(safe-area-inset-left, 0px)); padding-right: max(24px, env(safe-area-inset-right, 0px)); }
article { max-width: 860px; margin: 0 auto; background: var(--sheet); border: 1px solid var(--line); border-radius: 12px;
  padding: 44px 56px 56px; min-width: 0; }

article h1 { font: 700 34px/1.18 var(--display); margin: 0 0 16px; text-wrap: balance; letter-spacing: -.01em; }
article h2 { font: 700 27px/1.25 var(--display); margin: 56px -56px 18px; padding: 26px 56px 0; border-top: 1px solid var(--line);
  text-wrap: balance; scroll-margin-top: 70px; }
article h2 .eyebrow { display: block; margin-bottom: 6px; color: var(--accent); }
article h3 { font: 600 19px/1.35 var(--sans); margin: 40px 0 12px; scroll-margin-top: 70px; text-wrap: balance;
  display: flex; gap: 10px; align-items: baseline; }
article h3 .n { flex: none; font: 500 14px/1 var(--mono); color: var(--accent); background: var(--accent-wash);
  padding: 5px 8px; border-radius: 6px; }
article h4 { font: 600 16px/1.4 var(--sans); margin: 28px 0 8px; scroll-margin-top: 70px; }
article p, article li { max-width: 68ch; }
article a { color: var(--accent); text-underline-offset: 2px; }
article ul, article ol { padding-left: 1.35em; }
article li + li { margin-top: 4px; }
article hr { display: none; }
article strong { font-weight: 650; }
article blockquote { margin: 22px 0; padding: 14px 20px; background: var(--warn-wash); border: 1px solid #f1d9a6;
  border-radius: 10px; }
article blockquote > :first-child { margin-top: 0; }
article blockquote h3 { margin-top: 4px; color: var(--warn); }
article code { font: .86em var(--mono); background: var(--wash); border: 1px solid var(--line); padding: 1px 5px; border-radius: 5px; }
.table-wrap { overflow-x: auto; margin: 18px 0; border: 1px solid var(--line); border-radius: 10px; background: var(--sheet); }
table { border-collapse: collapse; width: max-content; min-width: 100%; font-size: 14px; line-height: 1.55; font-variant-numeric: tabular-nums; }
th, td { text-align: left; vertical-align: top; padding: 10px 14px; border-bottom: 1px solid var(--line); max-width: 30em; }
td code { white-space: nowrap; }
th { font-weight: 600; font-size: 12.5px; letter-spacing: .03em; color: var(--muted); background: var(--wash); white-space: nowrap; }
tbody tr:nth-child(even) td { background: #fafbfd; }
tr:last-child td { border-bottom: 0; }
figure.code { position: relative; margin: 18px 0; }
figure.code pre { margin: 0; overflow-x: auto; padding: 18px 20px; background: var(--wash); border: 1px solid var(--line);
  border-radius: 10px; font: 13.5px/1.6 var(--mono); color: var(--ink); }
figure.code pre code { background: none; border: 0; padding: 0; font-size: inherit; }
figure.code button { position: absolute; top: 10px; right: 10px; font: 600 12px var(--sans); color: var(--ink);
  background: var(--sheet); border: 1px solid var(--line); border-radius: 6px; padding: 5px 11px; cursor: pointer; }
figure.code button:hover, figure.code button:focus-visible { border-color: var(--accent); color: var(--accent); outline: none; }
.verdict { padding: 14px 18px; border-radius: 10px; border: 1px solid; }
.verdict.go { color: var(--go); background: var(--go-wash); }
.verdict.cond { color: var(--warn); background: var(--warn-wash); }
.verdict.stop { color: var(--stop); background: var(--stop-wash); }
input[type="checkbox"] { accent-color: var(--accent); }
.raw { white-space: pre-wrap; font: 13px/1.6 var(--mono); }
.scrim { display: none; }
@media (prefers-reduced-motion: no-preference) { html { scroll-behavior: smooth; } }
@media (prefers-reduced-motion: reduce) { .toc button.fold svg, .side { transition: none !important; } }

/* ---- narrow: the sidebar becomes a drawer ---- */
@media (max-width: 999px) {
  .side { width: min(320px, 86vw); transform: translateX(-100%); transition: transform .2s ease; box-shadow: none; }
  body.nav-open .side { transform: none; box-shadow: 0 0 0 100vmax rgba(20, 30, 45, .28); }
  .content { margin-left: 0; }
  .menu { display: inline-flex; }
  .bar { padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px)); }
  .desk { padding-block: 16px 56px; padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px)); }
  article { padding: 26px 20px 36px; border-radius: 10px; }
  article h1 { font-size: 27px; }
  article h2 { font-size: 23px; margin-left: -20px; margin-right: -20px; padding-left: 20px; padding-right: 20px; }
  .scrim { position: fixed; inset: 0; z-index: 15; }
  body.nav-open .scrim { display: block; }
}
</style>
<aside class="side" id="side" aria-label="Release navigation">
  <div class="brand">
    <span class="eyebrow">Deployment notes</span>
    <span class="name" id="brand-name">Release</span>
    <div class="meta" id="brand-meta"></div>
  </div>
  <nav class="toc" aria-label="Contents"><ol id="toc-list"></ol></nav>
</aside>
<div class="scrim" id="scrim"></div>
<div class="content">
  <div class="bar">
    <button type="button" class="menu" id="menu" aria-controls="side" aria-expanded="false">
      <svg width="16" height="16" viewBox="0 0 16 16" aria-hidden="true"><path d="M2 4h12M2 8h12M2 12h12" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" fill="none"/></svg>
      Contents
    </button>
    <div class="crumb" id="crumb" aria-live="polite"></div>
  </div>
  <div class="desk"><article id="notes"></article></div>
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
  var toc = document.getElementById("toc-list");
  var crumb = document.getElementById("crumb");
  if (!window.marked) {
    var raw = document.createElement("pre");
    raw.className = "raw"; raw.textContent = src; main.appendChild(raw);
    document.querySelector(".toc").hidden = true;
    return;
  }
  main.innerHTML = window.marked.parse(src, { gfm: true });

  // The release's name and verdict, read off the notes, head the sidebar.
  var h1 = main.querySelector("h1");
  var release = h1 ? h1.textContent.replace(/\s*[—–-]+\s*Deployment Notes\s*$/i, "").trim() : "";
  if (release) document.getElementById("brand-name").textContent = release;
  var meta = document.getElementById("brand-meta");
  var snap = src.match(/\*\*Snapshot:\*\*\s*([0-9]{4}-[0-9]{2}-[0-9]{2})/);

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

  var CHEVRON = '<svg viewBox="0 0 12 12" aria-hidden="true"><path d="M4 2.5 7.5 6 4 9.5" stroke="currentColor" stroke-width="1.6" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>';
  function setOpen(li, open) {
    li.classList.toggle("open", open);
    var b = li.querySelector("button.fold");
    if (b) b.setAttribute("aria-expanded", open ? "true" : "false");
  }

  // Sections and their numbered subsections (1.4, 3.1) - the numbers are how a
  // point is named in a call, so the sidebar shows them, folded under their
  // section. `spots` maps each heading to its sidebar link for the highlight.
  var used = {}, group = null, spots = [], verdict = "";
  main.querySelectorAll("h2, h3, h4").forEach(function (h) {
    var text = h.textContent.trim();
    var base = text.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "section";
    var id = base, n = 2; while (used[id]) { id = base + "-" + n++; } used[id] = true; h.id = id;

    if (/^H[34]$/.test(h.tagName) && /^verdict/i.test(text)) {
      verdict = /NO-GO|🔴/.test(text) ? "stop" : /CONDITION|🟠|🟡/.test(text) ? "cond" : "go";
      h.classList.add("verdict", verdict);
    }

    var top = h.tagName === "H2";
    var num = text.match(top ? /^(\d+)\.\s+(.*)$/ : /^(\d+\.\d+)\s+(.*)$/);
    if (!top && !(h.tagName === "H3" && num)) return;

    // In the article: a section gets a "Section N" eyebrow, a subsection its number as a tag.
    if (num) {
      h.textContent = "";
      if (top) {
        var eb = document.createElement("span"); eb.className = "eyebrow"; eb.textContent = "Section " + num[1];
        h.appendChild(eb); h.appendChild(document.createTextNode(num[2]));
      } else {
        var tag = document.createElement("span"); tag.className = "n"; tag.textContent = num[1];
        var label = document.createElement("span"); label.textContent = num[2];
        h.appendChild(tag); h.appendChild(label);
      }
    }

    var li = document.createElement("li"), a = document.createElement("a");
    a.href = "#" + id;
    if (top) {
      a.textContent = text;
      var row = document.createElement("div"); row.className = "row";
      row.appendChild(a); li.appendChild(row); toc.appendChild(li);
      group = { li: li, row: row, list: null };
      spots.push({ h: h, a: a, group: group, title: text, sub: "" });
    } else if (group) {
      if (!group.list) {
        var g = group, btn = document.createElement("button");
        btn.type = "button"; btn.className = "fold"; btn.innerHTML = CHEVRON;
        btn.setAttribute("aria-label", "Show or hide subsections");
        btn.addEventListener("click", function () { setOpen(g.li, !g.li.classList.contains("open")); });
        g.row.insertBefore(btn, g.row.firstChild);
        g.list = document.createElement("ol"); g.list.className = "subs";
        g.li.appendChild(g.list); setOpen(g.li, false);
      }
      var nn = document.createElement("span"); nn.className = "n"; nn.textContent = num[1];
      a.appendChild(nn); a.appendChild(document.createTextNode(num[2]));
      li.className = "sub"; li.appendChild(a); group.list.appendChild(li);
      spots.push({ h: h, a: a, group: group, title: group.row.querySelector("a").textContent, sub: text });
    }
  });
  if (!toc.children.length) document.querySelector(".toc").hidden = true;

  if (verdict) {
    var pill = document.createElement("span"); pill.className = "pill " + verdict;
    pill.textContent = verdict === "go" ? "GO" : verdict === "stop" ? "NO-GO" : "GO with conditions";
    meta.appendChild(pill);
  }
  if (snap) { var d = document.createElement("span"); d.textContent = "Snapshot " + snap[1]; meta.appendChild(d); }

  // Highlight the part being read, open its section, and name it in the top bar.
  var current;
  function mark(spot) {
    if (spot === current) return;
    if (current) current.a.classList.remove("active");
    current = spot;
    if (!spot) { crumb.textContent = release; return; }
    spot.a.classList.add("active");
    toc.querySelectorAll(":scope > li").forEach(function (li) { if (li !== spot.group.li && li.classList.contains("open") && !li.dataset.pinned) setOpen(li, false); });
    if (spot.group.list) setOpen(spot.group.li, true);
    crumb.innerHTML = "";
    var b = document.createElement("b"); b.textContent = spot.title; crumb.appendChild(b);
    if (spot.sub) crumb.appendChild(document.createTextNode("  ›  " + spot.sub));
  }
  function onScroll() {
    var y = 90, best = null;
    for (var i = 0; i < spots.length; i++) { if (spots[i].h.getBoundingClientRect().top <= y) best = spots[i]; else break; }
    mark(best);
  }
  var ticking = false;
  window.addEventListener("scroll", function () {
    if (ticking) return; ticking = true;
    requestAnimationFrame(function () { ticking = false; onScroll(); });
  }, { passive: true });
  // A section opened by hand stays open while reading elsewhere.
  toc.addEventListener("click", function (e) {
    var b = e.target.closest("button.fold");
    if (b) { var li = b.closest("li"); li.dataset.pinned = li.classList.contains("open") ? "1" : ""; }
  });

  // The drawer on narrow screens.
  var body = document.body, menu = document.getElementById("menu");
  function drawer(open) { body.classList.toggle("nav-open", open); menu.setAttribute("aria-expanded", open ? "true" : "false"); }
  menu.addEventListener("click", function () { drawer(!body.classList.contains("nav-open")); });
  document.getElementById("scrim").addEventListener("click", function () { drawer(false); });
  toc.addEventListener("click", function (e) { if (e.target.closest("a")) drawer(false); });
  document.addEventListener("keydown", function (e) { if (e.key === "Escape") drawer(false); });

  if (location.hash) {
    var target = document.getElementById(location.hash.slice(1));
    if (target) target.scrollIntoView();
  }
  onScroll();
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
