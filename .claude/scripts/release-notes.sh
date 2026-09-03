#!/usr/bin/env bash
#
# release-notes.sh - deterministic facts about a release, from a stated list of
# pull requests.
#
# A release here is not a branch. sport, payment, player, backend and admin all
# merged feature/m5.1 into main, but the same wave also merged hot/… and
# 5.1-additional/… straight to main, and mobile uses a scheme of its own. So the
# PR list is stated by the user and this script never tries to infer it.
#
# Everything comes from `gh`, never from repos/. Those checkouts cannot be
# refreshed from a session - guard.sh blocks `git fetch` under repos/ - so they
# are only as fresh as their last fetch. repos/ is read here only for slow-
# moving architecture: deploy triggers, proto copies, the deeplink registry.
#
# Those architecture reads come from repos/ and NEVER from spaces/. A space is
# a worktree on somebody's task branch, carrying half-finished and uncommitted
# work; reading a deploy trigger or a proto out of one describes that task, not
# the service. repos/ is the canonical checkout, and being read-only is exactly
# what makes it the right thing to read. Every local read goes through
# repo_path(), which resolves under repos/ or refuses.
#
# Usage:
#   release-notes.sh roll-call <name> <pr-url...>   cheap: state, size, checks
#   release-notes.sh report    <name> <pr-url...>   full: facts + extraction
#   release-notes.sh slash     <args...>            dispatcher for /release-notes
#
# Output is key<TAB>value lines. Multi-field records are documented at the head
# of the section that prints them.

# No `set -e`: a report that aborts on the first grep matching nothing reports
# less than no report at all. Failures are values here, printed as `warn`.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RELEASE_DIR="$ROOT/release"
TODAY="$(date +%Y-%m-%d)"

usage() { sed -n '3,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

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

# The one chokepoint for reading anything on disk. Takes a repo alias and an
# optional path under it, and resolves inside repos/ or prints nothing.
#
# Everything local goes through here so the "repos/, never spaces/" rule is a
# property of the script rather than a habit each caller has to remember. A
# caller that builds its own path is a bug; there is no second way in.
repo_path() {
  local al="$1" rel="${2:-}" p dir base real
  case "$al" in ""|-|*/*|.|..) return 1 ;; esac
  # A `..` anywhere in the relative part would climb out of repos/ and into
  # spaces/. Rejecting the segment is not enough on its own, so the resolved
  # path is checked below too - textual checks on an unresolved path are how
  # this kind of guard usually leaks.
  case "/$rel/" in */../*) return 1 ;; esac
  p="$ROOT/repos/$al${rel:+/$rel}"
  [ -e "$p" ] || return 1

  dir="$(dirname "$p")"; base="$(basename "$p")"
  real="$(cd "$dir" 2>/dev/null && pwd -P)" || return 1
  real="$real/$base"
  case "$real" in "$(cd "$ROOT/repos" && pwd -P)"/*) ;; *) return 1 ;; esac
  printf '%s' "$p"
}

# Local checkout whose origin matches <org>/<repo>, or "-" when not checked out.
# Both orgs in use are handled (Getswing-Team and getswing), and so is a repo
# that was never cloned here - the URL carries everything gh needs.
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
             (.reviewDecision // "NONE"), (.mergeStateStatus // "?"),
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

# Env keys a PR adds. The Go services declare service config in exactly one
# file, internal/infrastructure/config/config.go - but a one-off tool reads its
# own (player's credit backfill wants BACKEND_DB_DSN and SPORT_DB_DSN, and those
# must NOT go into the deployment config). So every file is scanned and the path
# is printed with the key: where it was read decides what to do about it.
# env<TAB>org/repo<TAB>KEY<TAB>file
facts_env() {
  local slug="$1" diff="$2"
  awk -v slug="$slug" '
    /^\+\+\+ b\// { f = substr($0, 7); next }
    /^\+/ {
      line = $0
      while (match(line, /os\.Getenv\("[A-Z0-9_]+"\)/)) {
        k = substr(line, RSTART + 11, RLENGTH - 13)
        print "env\t" slug "\t" k "\t" f
        line = substr(line, RSTART + RLENGTH)
      }
      if (f ~ /\.env\.example$/ && $0 ~ /^\+[A-Z][A-Z0-9_]*=/) {
        k = substr($0, 2); sub(/=.*/, "", k)
        print "env\t" slug "\t" k "\t" f
      }
    }
  ' "$diff" | sort -u
}

# migration<TAB>org/repo<TAB>path
facts_migrations() {
  local slug="$1" diff="$2"
  changed_files "$diff" \
    | grep -E '(^|/)migrations/.*\.(sql|ts|js)$' \
    | sed "s|^|migration	$slug	|"
}

# What merging actually does, read from the repo's own prod workflow.
# deploy<TAB>org/repo<TAB>trigger<TAB>note
facts_deploy() {
  local slug="$1" al wf on note
  al="$(alias_for "$slug")"
  [ "$al" = "-" ] && { printf 'deploy\t%s\t?\tnot checked out under repos/ - read its workflow by hand\n' "$slug"; return; }

  wf=""
  for f in deploy-prod.yml deploy-production.yml deploy.yml; do
    wf="$(repo_path "$al" ".github/workflows/$f")" && [ -n "$wf" ] && break
    wf=""
  done
  if [ -z "$wf" ]; then
    printf 'deploy\t%s\tnone\tNO WORKFLOW IN THE REPO - the production path is out of band, confirm it by hand\n' "$slug"
    return
  fi

  # Just the trigger shape - the whole `on:` block is unreadable as one line.
  on="$(awk '/^on:/{f=1;next} /^[a-z_]+:/{if(f)exit} f' "$wf" | tr -d ' ' | tr '\n' ' ')"
  trig=""
  case "$on" in *push:*) trig="push($(printf '%s' "$on" | sed -n 's/.*branches:\([^w]*\).*/\1/p' | tr -d '-' | awk '{print $1}'))" ;; esac
  case "$on" in *workflow_dispatch*) trig="${trig:+$trig + }manual" ;; esac
  case "$on" in *schedule*) trig="${trig:+$trig + }schedule" ;; esac

  case "$on" in
    *push:*main*)  note="merging to main deploys to production" ;;
    *push:*dev*)   note="deploys to DEV only - no production path in this repo, confirm how prod ships by hand" ;;
    *workflow_dispatch*) note="manual trigger only - merging does not deploy" ;;
    *) note="read $(basename "$wf") by hand" ;;
  esac
  printf 'deploy\t%s\t%s\t%s\n' "$slug" "$(basename "$wf"): ${trig:-?}" "$note"
}

# Protos are duplicated across repos, not shared, and already drifting: on
# 2026-09-03 credit.proto was 482 lines in player, 435 in sport, 327 in backend.
# A proto change in one repo is silently a release task in its consumers.
# proto<TAB>org/repo<TAB>path<TAB>other repos carrying a copy (differs?)
facts_proto() {
  local slug="$1" diff="$2" p base d others other al
  al="$(alias_for "$slug")"
  changed_files "$diff" | grep -E '\.proto$' | while read -r p; do
    base="$(basename "$p")"
    others=""
    for d in "$ROOT"/repos/*/; do
      [ -e "$d/.git" ] || continue
      other="$(basename "$d")"
      [ "$other" = "$al" ] && continue
      repo_path "$other" "proto/$base" >/dev/null || continue
      others="$others $other"
    done
    printf 'proto\t%s\t%s\t%s\n' "$slug" "$p" "${others:-no other repo carries a copy}"
  done
}

# Any deeplink a change emits. Ours are checked against the app's own registry
# of hosts; a third-party scheme (dana://pay, gojek://pay) is reported but not
# checked, since the app never routes it - it hands it to that wallet.
#
# The scheme is configurable and differs per environment (DeepLinkSchemePlayer,
# default getswing.dev), and fixtures use player://, pos://, swing:// freely -
# so the scheme says nothing. The HOST is what the app routes on, so that is
# what is checked. A host the registry knows is one the app can open; anything
# else is either another app's link or a link nothing will route.
# deeplink<TAB>org/repo<TAB>scheme://host<TAB>routable|NOT-IN-THE-APPS-REGISTRY
facts_deeplink() {
  local slug="$1" diff="$2" reg link host
  reg="$(repo_path mobile lib/utils/app_link_route.dart)"
  # A deeplink is a custom scheme. Ordinary web URLs in a diff are noise, so
  # http/https and the other standard schemes are excluded rather than matched.
  grep -E '^\+' "$diff" \
    | grep -oE '[a-z][a-z0-9.+-]*://[a-z0-9_-]+' \
    | grep -vE '^(https?|ftps?|mailto|wss?|file|data|git|ssh|postgres|redis|amqp)://' \
    | sort -u | while read -r link; do
      [ -n "$link" ] || continue
      host="${link##*://}"
      if [ ! -f "$reg" ]; then
        printf 'deeplink\t%s\t%s\tregistry not readable (mobile not checked out)\n' "$slug" "$link"
      elif grep -q "'$host'" "$reg" 2>/dev/null; then
        printf 'deeplink\t%s\t%s\troutable - the app has a route for "%s"\n' "$slug" "$link" "$host"
      else
        printf 'deeplink\t%s\t%s\tNOT-IN-THE-APPS-REGISTRY - another app'"'"'s link, or one nothing routes\n' "$slug" "$link"
      fi
    done
}

# Who the change faces. sport names its audience in the path; player only
# partly; payment not at all - for those the surface must be read off the
# handler, not the path, and this prints nothing rather than guessing.
# surface<TAB>org/repo<TAB>path<TAB>audience-or-channel
facts_surface() {
  local slug="$1" diff="$2"
  changed_files "$diff" | while read -r p; do
    case "$p" in
      */delivery/http/admin/*|*/delivery/http/admins/*) printf 'surface\t%s\t%s\tadmin panel\n' "$slug" "$p" ;;
      */delivery/http/player/*)   printf 'surface\t%s\t%s\tplayer app\n' "$slug" "$p" ;;
      */delivery/http/pos/*)      printf 'surface\t%s\t%s\tPOS app\n' "$slug" "$p" ;;
      */delivery/http/public/*)   printf 'surface\t%s\t%s\tpublic API\n' "$slug" "$p" ;;
      */delivery/http/developer/*) printf 'surface\t%s\t%s\tdeveloper API\n' "$slug" "$p" ;;
      */delivery/grpc/*)   printf 'surface\t%s\t%s\tgRPC - service to service, QA cannot reach directly\n' "$slug" "$p" ;;
      */delivery/rmq/*)    printf 'surface\t%s\t%s\tRabbitMQ consumer - reached by an upstream action\n' "$slug" "$p" ;;
      */delivery/sqs/*)    printf 'surface\t%s\t%s\tSQS consumer - reached by an upstream action\n' "$slug" "$p" ;;
      */delivery/job/*)    printf 'surface\t%s\t%s\tscheduled job - runs on its own clock\n' "$slug" "$p" ;;
      */delivery/socket/*) printf 'surface\t%s\t%s\trealtime socket\n' "$slug" "$p" ;;
      */templates/*email*|*/email/templates/*) printf 'surface\t%s\t%s\temail\n' "$slug" "$p" ;;
      */templates/*pdf*|*/pdf/templates/*)     printf 'surface\t%s\t%s\tPDF\n' "$slug" "$p" ;;
      pages/*) printf 'surface\t%s\t%s\tadmin screen /%s\n' "$slug" "$p" \
                 "$(printf '%s' "$p" | sed -e 's|^pages/||' -e 's|/index\.[jt]sx\?$||' -e 's|\.[jt]sx\?$||')" ;;
    esac
  done
}

# ---------------------------------------------------------------- extract --

# The team already writes the QA section, inside test names - it just never
# leaves the repo. Four patterns, all required:
#
#   1  ±func Test…            a removed/added pair IS the behaviour change
#   2  t.Run("…")             already plain English, lifted verbatim
#   3  name: "…"              table case, labelled
#   4  {"…", …}               table case, POSITIONAL - missed during design and
#                             it produced a false "no test coverage" report on
#                             the receipt-wording change. Not optional.
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
}

# A user-visible change with no test assertion is a release risk. On 2026-09-03
# this found two in sport #1040: the cashback narrowing in order/create.go and
# the admin booking_statuses filter, neither of which had a test.
# gap<TAB>org/repo<TAB>path
extract_gaps() {
  local slug="$1" diff="$2" tmp
  tmp="$WORK/gaps.$$"
  changed_files "$diff" > "$tmp.all"
  grep -E '(_test\.go|_test\.dart|\.test\.[jt]sx?|\.spec\.[jt]sx?)$' "$tmp.all" \
    | sed 's|/[^/]*$||' | sort -u > "$tmp.tested"

  grep -E '\.(go|ts|tsx|js|dart)$' "$tmp.all" \
    | grep -vE '(_test\.go|_test\.dart|\.test\.[jt]sx?|\.spec\.[jt]sx?)$' \
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
# moved on it hands back other people's changes too. Measured 2026-09-03:
# sport #1053 reports 13 changed files, and its diff carried 28 - the extra 15
# belonged to #1040 and appeared only because `dev` did not have them yet.
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

report() {
  local name="$1"; shift
  local url line slug num diff

  roll_call "$@"

  WORK="$(mktemp -d "${TMPDIR:-/tmp}/release-notes.XXXXXX")"

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

    facts_env       "$slug" "$diff"
    facts_migrations "$slug" "$diff"
    facts_proto     "$slug" "$diff"
    facts_deeplink  "$slug" "$diff"
    facts_surface   "$slug" "$diff"
    extract_tests   "$slug" "$diff"
    extract_gaps    "$slug" "$diff"
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
  kv note "facts come from gh only - repos/ is stale and cannot be fetched"
}

MODE="${1:-}"
[ $# -gt 0 ] && shift

case "$MODE" in
  roll-call|report)
    NAME="${1:-}"
    [ $# -gt 0 ] && shift
    if [ -z "$NAME" ]; then
      printf 'error\tname required: release-notes.sh %s <name> <pr-url...>\n' "$MODE"
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
