#!/usr/bin/env bash
#
# deployment-notes.sh - deterministic facts about a release, from a stated list
# of pull requests. /deployment-notes turns them into a dev section (what to
# prepare, in what order, how to undo it) and a QA section (what should be true).
#
# A release is not a branch. One wave routinely merges a feature branch into
# several repos and, the same day, hotfix branches straight into the same base,
# while an app ships on a scheme of its own. So the PR list is stated by the
# user and this script never tries to infer it.
#
# Every release fact comes from `gh`, never from repos/. Those checkouts are
# only as fresh as their last fetch. repos/ is read here only for slow-moving
# architecture: deploy triggers, contract copies, an app's route registry.
#
# What a path means in a given repo - who it faces, where its app keeps its
# route registry - is a fact about that repo, learned once by
# `/learn qa-release-note <repo>` into .claude/learned/<repo>/qa-release-note.md.
# This script reads the two machine-read sections of that file and guesses
# nothing when it is missing: it prints a `learn` record instead. How a repo is
# configured, deployed and rolled back is learned by `/learn dev-deployment-note`;
# no section of that file is machine-read, so the command reads it, not this.
#
# Those architecture reads come from a git ref, NEVER from a working tree. A
# task works on its own branch - in a space's worktree, or in place in
# repos/<repo> itself - carrying half-finished and uncommitted work; reading a
# deploy trigger or a proto out of that describes the task, not the service.
# So every local read goes through repo_path(), which reads the file from the
# repo's default branch (origin/HEAD) whatever its checkout is on, and refuses
# anything else.
#
# Usage:
#   deployment-notes.sh roll-call <name> <pr-url...>   cheap: state, size, checks
#   deployment-notes.sh report    <name> <pr-url...>   full: facts + extraction
#   deployment-notes.sh facts     <org/repo> <diff>    local facts for one saved diff, no gh
#   deployment-notes.sh slash     <args...>            dispatcher for /deployment-notes
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

usage() { sed -n '3,39p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

warn() { printf 'warn\t%s\n' "$1"; }
kv()   { printf '%s\t%s\n' "$1" "$2"; }

WORK=""
cleanup() { [ -n "$WORK" ] && [ -d "$WORK" ] && rm -rf "$WORK"; }
trap cleanup EXIT

# ------------------------------------------------------------------ inputs --

# A PR URL -> "<org>/<repo>	<number>". Anything else is skipped with a warn.
#
# URLs arrive pasted, so they carry whatever came with them: a leading "- "
# from a markdown list, surrounding whitespace, a trailing slash or #anchor.
# Strip that rather than making the caller tidy it. A URL with no number
# (".../pull/") is not a pull request and falls through to the warn.
parse_pr() {
  printf '%s' "$1" \
    | sed -e 's/^[[:space:]]*[-*][[:space:]]*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    | sed -n 's|^https://github.com/\([^/]*\)/\([^/]*\)/pull/\([0-9][0-9]*\).*$|\1/\2\t\3|p'
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

# The one chokepoint for reading anything local. Takes a repo alias and a path
# inside it, reads that file at canonical_ref, and prints the path of a copy in
# the scratch directory - or prints nothing if the file is not on that ref.
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

# Local checkout whose origin matches <org>/<repo>, or "-" when not checked out.
# Matching is on the org/repo slug, so a repo cloned under a renamed org still
# resolves, and one never cloned here is fine - the URL carries all gh needs.
alias_for() {
  local slug="$1" d url
  for d in "$ROOT"/repos/*/; do
    [ -e "$d/.git" ] || continue
    url="$(git -C "$d" remote get-url origin 2>/dev/null)"
    case "$url" in
      *"$slug".git|*"$slug") basename "$d"; return 0 ;;
    esac
  done
  printf '%s' '-'
}

# --------------------------------------------------------------- roll call --

# pr<TAB>num<TAB>org/repo<TAB>state<TAB>head<TAB>base<TAB>+a/-d<TAB>files<TAB>review<TAB>checks<TAB>title
roll_call() {
  local url slug num meta seen_repos="" repo_base="" line

  for url in "$@"; do
    line="$(parse_pr "$url")"
    if [ -z "$line" ]; then
      warn "not a pull request URL, skipped: $url"
      continue
    fi
    slug="$(printf '%s' "$line" | cut -f1)"
    num="$(printf '%s' "$line" | cut -f2)"
    # Rebuild the URL from the parsed parts rather than reusing what was
    # pasted: whatever came with it - a bullet, a trailing slash, an anchor -
    # is gone by construction, and gh sees one canonical form.
    url="https://github.com/$slug/pull/$num"

    meta="$(gh pr view "$url" \
      --json number,state,title,headRefName,baseRefName,additions,deletions,changedFiles,reviewDecision,mergeStateStatus,statusCheckRollup \
      --jq '[
             .state, .headRefName, .baseRefName,
             ("+\(.additions)/-\(.deletions)"), (.changedFiles|tostring),
             (if (.reviewDecision // "") == "" then "NONE" else .reviewDecision end), (.mergeStateStatus // "?"),
             ([.statusCheckRollup[]? | select(.conclusion != null and .conclusion != "SUCCESS" and .conclusion != "NEUTRAL" and .conclusion != "SKIPPED")] | length | tostring),
             .title
            ] | @tsv' 2>/dev/null)"

    if [ -z "$meta" ]; then
      warn "could not read $slug#$num - check gh auth and that the PR exists"
      continue
    fi
    printf 'pr\t%s\t%s\t%s\n' "$num" "$slug" "$meta"
    printf 'alias\t%s\t%s\n' "$slug" "$(alias_for "$slug")"

    case " $seen_repos " in
      *" $slug "*) ;;
      *) seen_repos="$seen_repos $slug"
         repo_base="$repo_base$slug	$(printf '%s' "$meta" | cut -f3)
" ;;
    esac
  done

  missed_check "$repo_base" "$@"
}

# The duplicate-PR check. Explicit lists cannot discover a PR nobody named, and
# that was the top blocker of the 2026-09-02 release: four PRs carried content
# already inside the release PRs, squash merge was on in all three repos, and
# every one of them was merged anyway. So: for each repo named, list the OTHER
# open PRs into the same base and print them. A check, never a discovery step.
#
# missed<TAB>org/repo<TAB>num<TAB>head<TAB>title
missed_check() {
  local repo_base="$1"; shift
  local slug base others num url in_list

  printf '%s' "$repo_base" | while IFS="$(printf '\t')" read -r slug base; do
    [ -n "$slug" ] || continue
    others="$(gh pr list --repo "$slug" --base "$base" --state open --limit 50 \
      --json number,headRefName,title \
      --jq '.[] | [(.number|tostring), .headRefName, .title] | @tsv' 2>/dev/null)"
    [ -n "$others" ] || continue

    printf '%s\n' "$others" | while IFS="$(printf '\t')" read -r num rest; do
      [ -n "$num" ] || continue
      in_list=no
      for url in "$@"; do
        case "$url" in *"/$slug/pull/$num"|*"/$slug/pull/$num/"*|*"/$slug/pull/$num"[!0-9]*) in_list=yes ;; esac
      done
      [ "$in_list" = yes ] && continue
      printf 'missed\t%s\t%s\t%s\n' "$slug" "$num" "$rest"
    done
  done
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

# Env keys a PR adds, and the file that reads each one. Where a key is read
# decides what to do with it: service configuration belongs in the deployment
# config, a one-off tool's key never does. So every file is scanned and the path
# is printed with the key. Covers the common forms: Go os.Getenv / LookupEnv,
# Node process.env.KEY and process.env["KEY"], Python os.environ / os.getenv,
# Ruby ENV["KEY"], and new KEY= lines in any .env.example.
# env<TAB>org/repo<TAB>KEY<TAB>file
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

# migration<TAB>org/repo<TAB>path
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
# ddl<TAB>org/repo<TAB>path<TAB>kind<TAB>statement
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

# Dependency lines a PR adds or removes in a manifest. A - and a + on the same
# name is a bump, and the reader pairs them. Lockfiles are left out - they
# restate the manifest at length - and so are Go's indirect requirements and a
# package.json's own version field.
# dep<TAB>org/repo<TAB>manifest<TAB>+|-<TAB>line
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
# infra<TAB>org/repo<TAB>path
facts_infra() {
  local slug="$1" p
  changed_files "$2" \
    | grep -E '(^|/)(Dockerfile[^/]*|[^/]*\.dockerfile|docker-compose[^/]*\.ya?ml|compose\.ya?ml|Procfile|fly\.toml|app\.ya?ml|serverless\.ya?ml|ecosystem\.config\.[cm]?js|nginx[^/]*\.conf|Makefile|[^/]*\.tf|[^/]*\.tfvars)$|^\.github/workflows/|(^|/)(k8s|kubernetes|helm|charts|deploy|deployments|terraform)/' \
    | while read -r p; do printf 'infra\t%s\t%s\n' "$slug" "$p"; done
}

# What merging actually does, read from the repo's own prod workflow.
# deploy<TAB>org/repo<TAB>trigger<TAB>note
facts_deploy() {
  local slug="$1" al wf on note f trig
  al="$(alias_for "$slug")"
  [ "$al" = "-" ] && { printf 'deploy\t%s\t?\tnot checked out under repos/ - read its workflow by hand\n' "$slug"; return; }

  wf=""
  for f in deploy-prod.yml deploy-production.yml deploy.yml deploy-prod.yaml deploy-production.yaml deploy.yaml; do
    wf="$(repo_path "$al" ".github/workflows/$f")" && [ -n "$wf" ] && break
    wf=""
  done
  if [ -z "$wf" ]; then
    printf 'deploy\t%s\tnone\tno deploy workflow under a common name - the learned file or the repo says how production ships; confirm it by hand\n' "$slug"
    return
  fi

  # Just the trigger shape - the whole `on:` block is unreadable as one line.
  on="$(awk '/^on:/{f=1;next} /^[a-z_]+:/{if(f)exit} f' "$wf" | tr -d ' ' | tr '\n' ' ')"
  trig=""
  case "$on" in *push:*) trig="push($(printf '%s' "$on" | sed -n 's/.*branches:\([^w]*\).*/\1/p' | tr -d '-' | awk '{print $1}'))" ;; esac
  case "$on" in *workflow_dispatch*) trig="${trig:+$trig + }manual" ;; esac
  case "$on" in *schedule*) trig="${trig:+$trig + }schedule" ;; esac

  case "$on" in
    *push:*main*|*push:*master*) note="merging to the default branch deploys to production" ;;
    *push:*dev*)   note="deploys to DEV only - no production path in this workflow, confirm how prod ships by hand" ;;
    *workflow_dispatch*) note="manual trigger only - merging does not deploy" ;;
    *) note="read $(basename "$wf") by hand" ;;
  esac
  printf 'deploy\t%s\t%s\t%s\n' "$slug" "$(basename "$wf"): ${trig:-?}" "$note"
}

# Contracts copied between repos rather than shared - protos, schemas - drift,
# and a change in one is silently a release task in every repo holding a copy.
# A copy is a file of the same name anywhere in another checkout's default
# branch.
# proto<TAB>org/repo<TAB>path<TAB>other repos carrying a copy
facts_proto() {
  local slug="$1" diff="$2" p base d others other al ref
  al="$(alias_for "$slug")"
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
# deeplink<TAB>org/repo<TAB>scheme://host<TAB>routable|NOT-IN-THE-APPS-REGISTRY|no registry
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
# surface<TAB>org/repo<TAB>path<TAB>audience-or-channel
# learn<TAB>org/repo<TAB>what is missing
facts_surface() {
  local slug="$1" diff="$2" al f rules p glob label hit
  al="$(alias_for "$slug")"
  if ! f="$(learned_release "$al")"; then
    printf 'learn\t%s\tno surfaces learned for this repo - /learn qa-release-note %s, or read the audience off each handler\n' "$slug" "${al/-/<repo>}"
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
# test<TAB>org/repo<TAB>+|-<TAB>func|case<TAB>text
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
# gap<TAB>org/repo<TAB>path
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

# Fetch a PR's diff, restricted to the files the PR actually touches.
#
# `gh pr diff` compares the base branch tip with the head, so when the base has
# moved on it hands back other people's changes too. Measured 2026-09-03: a PR
# reporting 13 changed files carried 28 in its diff - the extra 15 belonged to
# another PR and appeared only because the base did not have them yet.
# Extracting from that unfiltered diff credits one PR with another's behaviour
# changes, which is worse than missing them.
#
# So the PR's own file list is authoritative, and the diff is filtered to it.
pr_diff() {
  local url="$1" out="$2" raw="$2.raw" list="$2.files"

  gh pr diff "$url" > "$raw" 2>/dev/null || return 1
  [ -s "$raw" ] || return 1

  if ! gh pr view "$url" --json files --jq '.files[].path' > "$list" 2>/dev/null \
     || [ ! -s "$list" ]; then
    warn "could not read the file list for $url - extracting from the whole diff, which may include changes from other PRs"
    mv "$raw" "$out"
    return 0
  fi

  awk '
    function flush() { if (keepit && buf != "") printf "%s", buf; buf = ""; keepit = 0 }
    FNR == NR            { keep[$0] = 1; next }
    /^diff --git /       { flush(); buf = $0 "\n"; next }
    /^\+\+\+ b\//        { f = substr($0, 7); if (f in keep) keepit = 1 }
                         { buf = buf $0 "\n" }
    END                  { flush() }
  ' "$list" "$raw" > "$out"

  rm -f "$raw" "$list"
  [ -s "$out" ]
}

# ------------------------------------------------------------------ report --

# Everything this script can say about one diff without asking gh.
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

report() {
  local name="$1"; shift
  local url line slug num diff

  roll_call "$@"

  WORK="$(mktemp -d "${TMPDIR:-/tmp}/deployment-notes.XXXXXX")"

  for url in "$@"; do
    line="$(parse_pr "$url")"
    [ -n "$line" ] || continue
    slug="$(printf '%s' "$line" | cut -f1)"
    num="$(printf '%s' "$line" | cut -f2)"
    url="https://github.com/$slug/pull/$num"
    diff="$WORK/$(printf '%s' "$slug" | tr '/' '-')-$num.diff"

    if ! pr_diff "$url" "$diff"; then
      warn "no diff for $slug#$num - it may be empty, or too large for gh"
      continue
    fi
    kv "diff-lines" "$slug#$num	$(wc -l < "$diff" | tr -d ' ')"

    local_facts "$slug" "$diff"
  done

  # One deploy line per repo, not per PR.
  for url in "$@"; do
    line="$(parse_pr "$url")"
    [ -n "$line" ] || continue
    printf '%s\n' "$(printf '%s' "$line" | cut -f1)"
  done | sort -u | while read -r slug; do facts_deploy "$slug"; done
}

# ------------------------------------------------------------------- shell --

header() {
  local name="$1" prev
  kv mode "$MODE"
  kv release "$name"
  kv date "$TODAY"
  kv outfile "release/$TODAY-$name.md"
  prev="$(ls -1 "$RELEASE_DIR"/*.md 2>/dev/null | grep -v 'README\.md$' | sort | tail -1)"
  [ -n "$prev" ] && kv prev "release/$(basename "$prev")"
  kv note "release facts come from gh only; repos/ is read at its default branch for architecture"
}

MODE="${1:-}"
[ $# -gt 0 ] && shift

case "$MODE" in
  roll-call|report)
    NAME="${1:-}"
    [ $# -gt 0 ] && shift
    if [ -z "$NAME" ]; then
      printf 'error\tname required: deployment-notes.sh %s <name> <pr-url...>\n' "$MODE"
      exit 2
    fi
    # Lower-case, digits, dash and dot. Dots because release names are versions
    # as often as words - the runbooks on disk are 2026-09-02-5.1.md. What is
    # refused is anything that would not survive being a filename: spaces,
    # slashes, and a leading dot.
    case "$NAME" in
      .*|*[!a-z0-9.-]*) printf 'error\tname must be lower-case letters, digits, - and . : %s\n' "$NAME"; exit 2 ;;
    esac
    header "$NAME"
    if [ $# -eq 0 ]; then
      warn "no pull request URLs given - paste them, one per line"
      exit 0
    fi
    command -v gh >/dev/null 2>&1 || { printf 'error\tgh is not installed\n'; exit 2; }
    if [ "$MODE" = roll-call ]; then roll_call "$@"; else report "$NAME" "$@"; fi
    ;;
  facts)
    [ $# -eq 2 ] && [ -f "$2" ] || { printf 'error\tusage: deployment-notes.sh facts <org/repo> <diff-file>\n'; exit 2; }
    WORK="$(mktemp -d "${TMPDIR:-/tmp}/deployment-notes.XXXXXX")"
    local_facts "$1" "$2"
    ;;
  slash)
    MODE=roll-call
    exec "${BASH_SOURCE[0]}" roll-call "$@"
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
