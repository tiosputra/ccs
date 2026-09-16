#!/usr/bin/env bash
#
# graph.sh - code-review-graph for every checkout and space, kept outside them.
#
# code-review-graph parses a repo into a call/import graph that answers "what
# does this change touch" without reading the whole codebase. Left alone it
# writes .code-review-graph/ into the repo it reads, which is a write into
# repos/ or noise in a space's pull request. This script keeps every graph at
# the workspace root instead, laid out like the workspace:
#
#   .code-review-graph/repos/<repo>/          graph of repos/<repo>
#   .code-review-graph/spaces/<task>/<repo>/  graph of spaces/<task>/<repo>
#
# Usage:
#   graph.sh status                          every checkout, space and orphaned graph
#   graph.sh build <target>|all              full rebuild; `all` is every repos/ checkout
#   graph.sh review <task>[/<repo>] [--base <ref>]
#                                            rebuild if stale, then the blast radius vs base
#   graph.sh run <target> <query> [args...]  one read-only code-review-graph query
#   graph.sh drop <task> [repo]              delete a space's graphs (space.sh remove calls this)
#   graph.sh prune                           delete graphs whose space no longer exists
#   graph.sh slash <args...>                 dispatcher for the /graph command
#
# <target> is <repo> for repos/<repo>, or <task>/<repo> for a space worktree.
#
# status rows:
#   graph<TAB>target<TAB>kind<TAB>state<TAB>built<TAB>files<TAB>nodes
# kind is repo or space. state is fresh, stale (code, uncommitted work or
# .code-review-graphignore changed since the build), missing, or orphan.
#
# Writes only under .code-review-graph/. Never writes to a repo, a worktree, or
# a git index: builds read a scratch copy of the index in which untracked files
# are marked intent-to-add, so work not yet committed is in the graph, and
# the .code-review-graphignore paths are removed.

# No `set -e`: status is a report, and build checks each step itself so a
# failed build can leave the previous graph in place.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPOS_DIR="$ROOT/repos"
SPACES_DIR="$ROOT/spaces"
GRAPHS="$ROOT/.code-review-graph"
IGNORE_FILE="$ROOT/.code-review-graphignore"
CRG=code-review-graph

# The tool keeps a registry and caches under $CRG_HOME; keep those here too.
export CRG_HOME="$GRAPHS/home"

# Queries `run` passes through. Everything else writes - build, update, forget,
# install, watch, serve, embed - or wants the default data dir inside the repo.
READ_ONLY_QUERIES="query impact search detect-changes flows flow communities community architecture large-functions dead-code status"

usage() { sed -n '3,34p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
die()   { printf 'error\t%s\n' "$*" >&2; exit 1; }
rel()   { printf '%s\n' "${1#"$ROOT"/}"; }

digest() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 1; else sha1sum; fi | cut -c1-12
}

crg_installed() { command -v "$CRG" >/dev/null 2>&1; }
crg_version()   { "$CRG" --version 2>/dev/null | awk '{print $NF}'; }
need_crg() {
  crg_installed || die "code-review-graph is not installed - pipx install code-review-graph"
}

# Globals set by resolve and scratch_index. Both are called directly, never in
# $(...), so what they set survives - and so does the temp-file list the EXIT
# trap cleans up.
T_NAME="" T_KIND="" T_DIR="" T_DATA="" RESOLVE_ERR="" IDX="" EXCLUDED=0
TMP_FILES=""
cleanup() { [ -z "$TMP_FILES" ] || rm -rf $TMP_FILES; }
trap cleanup EXIT

# ----------------------------------------------------------------- targets --

# resolve <target> - sets T_NAME, T_KIND, T_DIR, T_DATA, or RESOLVE_ERR and fails.
resolve() {
  local t="${1%/}"
  T_NAME="" T_KIND="" T_DIR="" T_DATA="" RESOLVE_ERR=""
  case "$t" in
    ""|*..*|/*|*/*/*) RESOLVE_ERR="'$1' is not a target - use <repo> or <task>/<repo>"; return 1 ;;
    */*)
      if [ ! -e "$SPACES_DIR/$t/.git" ]; then
        RESOLVE_ERR="no space worktree at spaces/$t - /space list shows what exists"; return 1
      fi
      T_KIND=space T_DIR="$SPACES_DIR/$t" T_DATA="$GRAPHS/spaces/$t" ;;
    *)
      if [ ! -e "$REPOS_DIR/$t/.git" ]; then
        if [ -d "$SPACES_DIR/$t" ]; then
          RESOLVE_ERR="'$t' is a task, not a repo - name one of its repos: $t/<repo>"
        else
          RESOLVE_ERR="no checkout at repos/$t - /space repos lists them"
        fi
        return 1
      fi
      T_KIND=repo T_DIR="$REPOS_DIR/$t" T_DATA="$GRAPHS/repos/$t" ;;
  esac
  T_NAME="$t"
}

repo_names() {
  local d
  for d in "$REPOS_DIR"/*/; do
    [ -e "$d/.git" ] && basename "$d"
  done
}

# Worktrees of one task, as <task>/<repo>.
space_targets() {
  local d
  for d in "$SPACES_DIR/$1"/*/; do
    [ -e "$d/.git" ] && printf '%s/%s\n' "$1" "$(basename "$d")"
  done
}

all_space_targets() {
  local d
  for d in "$SPACES_DIR"/*/; do
    [ -d "$d" ] && space_targets "$(basename "$d")"
  done
}

# ------------------------------------------------------------------- index --

# The .code-review-graphignore patterns as git glob pathspecs, one per line.
ignore_pathspecs() {
  [ -f "$IGNORE_FILE" ] || return 0
  awk '
    { sub(/[[:space:]]+$/, "") }
    /^[[:space:]]*(#|$)/ || /^!/ { next }
    {
      p = $0; dir = 0; anchored = 0
      if (p ~ /\/$/) { dir = 1; sub(/\/$/, "", p) }
      if (p ~ /^\//) { anchored = 1; sub(/^\//, "", p) }
      if (p ~ /\//)  { anchored = 1 }
      out = (anchored ? "" : "**/") p (dir ? "/**" : "")
      print ":(glob)" out
    }' "$IGNORE_FILE"
}

# scratch_index <dir> <exclude:yes|no> - sets IDX to a throwaway copy of <dir>'s
# index with untracked files marked intent-to-add and, when asked, the ignored
# paths removed; EXCLUDED to how many were removed.
scratch_index() {
  local dir="$1" exclude="$2" real idx specs
  IDX="" EXCLUDED=0
  real="$(git -C "$dir" rev-parse --path-format=absolute --git-path index)" || return 1
  idx="$(mktemp "${TMPDIR:-/tmp}/graph-index.XXXXXX")" || return 1
  TMP_FILES="$TMP_FILES $idx"
  cp "$real" "$idx" || return 1
  git -C "$dir" ls-files -z --others --exclude-standard \
    | GIT_INDEX_FILE="$idx" xargs -0 git -C "$dir" add -N -- 2>/dev/null
  if [ "$exclude" = yes ]; then
    specs="$(ignore_pathspecs)"
    if [ -n "$specs" ]; then
      EXCLUDED="$(printf '%s\n' "$specs" | tr '\n' '\0' \
        | GIT_INDEX_FILE="$idx" xargs -0 git -C "$dir" ls-files -z -- | tr -cd '\0' | wc -c | tr -d ' ')"
      printf '%s\n' "$specs" | tr '\n' '\0' \
        | GIT_INDEX_FILE="$idx" xargs -0 git -C "$dir" ls-files -z -- \
        | GIT_INDEX_FILE="$idx" git -C "$dir" update-index -z --force-remove --stdin
    fi
  fi
  IDX="$idx"
}

# ------------------------------------------------------------- fingerprint --

# What a graph was built from: HEAD, uncommitted changes, untracked file
# contents, the ignore file, and the tool version. Equal fingerprint, same graph.
fingerprint() {
  local dir="$1" f
  {
    git -C "$dir" rev-parse HEAD
    git -C "$dir" diff HEAD --binary --no-ext-diff 2>/dev/null
    git -C "$dir" ls-files --others --exclude-standard | LC_ALL=C sort | while IFS= read -r f; do
      printf -- '-- %s\n' "$f"
      cat "$dir/$f" 2>/dev/null
    done
    [ -f "$IGNORE_FILE" ] && cat "$IGNORE_FILE"
    crg_version
  } | digest
}

# crg_at <data-dir> <repo-dir> <subcommand> [args...] - the only way this script
# runs code-review-graph. Without CRG_DATA_DIR the tool falls back to
# <repo>/.code-review-graph/, which is a write into the checkout. So a data dir
# outside .code-review-graph/ is refused, and one that appears inside the
# checkout anyway is reported as an error rather than passed over.
crg_at() {
  local data="$1" dir="$2" rc had=no
  shift 2
  case "$data" in
    "$GRAPHS"/?*) ;;
    *) printf 'error\trefusing to run code-review-graph with data dir "%s" - graphs live under %s\n' \
         "$data" "$(rel "$GRAPHS")" >&2
       return 1 ;;
  esac
  [ -e "$dir/.code-review-graph" ] && had=yes
  if [ -n "$IDX" ]; then
    GIT_INDEX_FILE="$IDX" CRG_DATA_DIR="$data" "$CRG" "$@" --repo "$dir"; rc=$?
  else
    CRG_DATA_DIR="$data" "$CRG" "$@" --repo "$dir"; rc=$?
  fi
  if [ "$had" = no ] && [ -e "$dir/.code-review-graph" ]; then
    printf 'error\tcode-review-graph wrote %s, inside a checkout - stop and tell the user\n' \
      "$(rel "$dir/.code-review-graph")" >&2
    return 1
  fi
  return "$rc"
}

stamp_value() { [ -f "$1/built.tsv" ] && awk -F'\t' -v k="$2" '$1==k {print $2; exit}' "$1/built.tsv"; }
json_int()    { sed -n "s/.*\"$1\": \([0-9][0-9]*\).*/\1/p"; }

# -------------------------------------------------------------------- build --

# build_one <target> [fp-now] [label] - full rebuild into a temp dir, swapped in
# only on success. Prints one "<label><TAB><target>..." row, or an error row.
build_one() {
  local fp="${2:-}" label="${3:-built}" tmp log json
  resolve "$1" || { printf 'error\t%s\n' "$RESOLVE_ERR"; return 1; }
  [ -n "$fp" ] || fp="$(fingerprint "$T_DIR")"
  mkdir -p "$(dirname "$T_DATA")" || return 1
  tmp="$T_DATA.building.$$"
  TMP_FILES="$TMP_FILES $tmp"
  rm -rf "$tmp"; mkdir -p "$tmp"
  log="$tmp/build.log"

  scratch_index "$T_DIR" yes || { printf 'error\t%s\tcould not copy the git index\n' "$T_NAME"; return 1; }
  if ! crg_at "$tmp" "$T_DIR" build -q >"$log" 2>&1; then
    printf 'error\t%s\tbuild failed - last lines of the log:\n' "$T_NAME"
    tail -5 "$log" | sed 's/^/  /'
    return 1
  fi
  json="$(crg_at "$tmp" "$T_DIR" status --json 2>>"$log")"
  {
    printf 'target\t%s\n'      "$T_NAME"
    printf 'dir\t%s\n'         "$(rel "$T_DIR")"
    printf 'built\t%s\n'       "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'head\t%s\n'        "$(git -C "$T_DIR" rev-parse HEAD)"
    printf 'fingerprint\t%s\n' "$fp"
    printf 'files\t%s\n'       "$(printf '%s' "$json" | json_int files)"
    printf 'nodes\t%s\n'       "$(printf '%s' "$json" | json_int nodes)"
    printf 'edges\t%s\n'       "$(printf '%s' "$json" | json_int edges)"
    printf 'excluded\t%s\n'    "$EXCLUDED"
    printf 'crg\t%s\n'         "$(crg_version)"
  } > "$tmp/built.tsv"

  rm -rf "$T_DATA" && mv "$tmp" "$T_DATA" || { printf 'error\t%s\tcould not move the graph into place\n' "$T_NAME"; return 1; }
  printf '%s\t%s\tfiles %s\tnodes %s\texcluded %s\t%s\n' "$label" "$T_NAME" \
    "$(stamp_value "$T_DATA" files)" "$(stamp_value "$T_DATA" nodes)" \
    "$(stamp_value "$T_DATA" excluded)" "$(rel "$T_DATA")"
}

cmd_build() {
  local t failed=0
  need_crg
  [ $# -eq 1 ] || die "usage: graph.sh build <repo> | <task>/<repo> | all"
  if [ "$1" = all ]; then
    for t in $(repo_names); do build_one "$t" || failed=$((failed + 1)); done
  else
    build_one "$1" || failed=1
  fi
  [ "$failed" -eq 0 ]
}

# ------------------------------------------------------------------- status --

status_row() {
  local target="$1" kind="$2" dir="$3" data="$4" state built files nodes
  built="$(stamp_value "$data" built)"; [ -n "$built" ] || built=-
  files="$(stamp_value "$data" files)"; [ -n "$files" ] || files=-
  nodes="$(stamp_value "$data" nodes)"; [ -n "$nodes" ] || nodes=-
  if [ ! -e "$dir/.git" ]; then state=orphan
  elif [ ! -f "$data/built.tsv" ]; then state=missing
  elif [ "$(stamp_value "$data" fingerprint)" = "$(fingerprint "$dir")" ]; then state=fresh
  else state=stale
  fi
  printf 'graph\t%s\t%s\t%s\t%s\t%s\t%s\n' "$target" "$kind" "$state" "$built" "$files" "$nodes"
}

# Graph dirs whose worktree is gone, as <task>/<repo>.
orphan_targets() {
  local d t
  [ -d "$GRAPHS/spaces" ] || return 0
  for d in "$GRAPHS"/spaces/*/*/; do
    [ -f "$d/built.tsv" ] || continue
    t="${d%/}"; t="${t#"$GRAPHS"/spaces/}"
    [ -e "$SPACES_DIR/$t/.git" ] || printf '%s\n' "$t"
  done
}

cmd_status() {
  local t
  if crg_installed; then printf 'installed\t%s\n' "$(crg_version)"; else printf 'installed\tno\tpipx install code-review-graph\n'; fi
  printf 'ignore_file\t%s\n' "$(rel "$IGNORE_FILE")"
  for t in $(repo_names);         do status_row "$t" repo  "$REPOS_DIR/$t"  "$GRAPHS/repos/$t"; done
  for t in $(all_space_targets);  do status_row "$t" space "$SPACES_DIR/$t" "$GRAPHS/spaces/$t"; done
  for t in $(orphan_targets);     do status_row "$t" space "$SPACES_DIR/$t" "$GRAPHS/spaces/$t"; done
}

# ------------------------------------------------------------------- review --

# The commit a space's repo is compared against: the merge-base with the ref
# the space was created from, so a rebase onto a newer base does not drag the
# base's own commits into the review. Prints "<sha><TAB><ref><TAB><how>".
review_base() {
  local task="$1" repo="$2" dir="$3" given="$4" ref sha mb
  if [ -n "$given" ]; then
    mb="$(git -C "$dir" merge-base HEAD "$given" 2>/dev/null)" \
      || { echo "cannot find a merge-base between HEAD and '$given'"; return 1; }
    printf '%s\t%s\tgiven\n' "$mb" "$given"; return 0
  fi
  ref="$(awk -F'\t' -v r="$repo" '$1=="base" && $2==r {print $3; exit}' "$SPACES_DIR/$task/.space" 2>/dev/null)"
  sha="$(awk -F'\t' -v r="$repo" '$1=="base" && $2==r {print $4; exit}' "$SPACES_DIR/$task/.space" 2>/dev/null)"
  if [ -n "$ref" ] && mb="$(git -C "$dir" merge-base HEAD "$ref" 2>/dev/null)"; then
    printf '%s\t%s\tmerge-base\n' "$mb" "$ref"
  elif [ -n "$sha" ] && git -C "$dir" cat-file -e "$sha^{commit}" 2>/dev/null; then
    printf '%s\t%s\trecorded\n' "$sha" "${ref:--}"
  else
    echo "spaces/$task/.space records no base for $repo - pass --base <ref>"; return 1
  fi
}

review_one() {
  local target="$1" given="$2" task repo base sha fp changed
  resolve "$target" || { printf 'error\t%s\n' "$RESOLVE_ERR"; return 1; }
  [ "$T_KIND" = space ] || { printf 'error\t%s\n' "review compares a space against its base - '$target' is a checkout, use <task>/<repo>"; return 1; }
  task="${T_NAME%%/*}" repo="${T_NAME#*/}"
  base="$(review_base "$task" "$repo" "$T_DIR" "$given")" || { printf 'error\t%s\t%s\n' "$T_NAME" "$base"; return 1; }
  sha="${base%%	*}"

  printf 'review\t%s\n' "$T_NAME"
  printf 'dir\t%s\n'    "$(rel "$T_DIR")"
  printf 'base\t%s\n'   "$base"

  fp="$(fingerprint "$T_DIR")"
  if [ "$(stamp_value "$T_DATA" fingerprint)" = "$fp" ]; then
    printf 'graph\tfresh\tfiles %s\tnodes %s\n' "$(stamp_value "$T_DATA" files)" "$(stamp_value "$T_DATA" nodes)"
  else
    build_one "$T_NAME" "$fp" "graph	rebuilt" || return 1
  fi

  changed="$( { git -C "$T_DIR" diff --name-only "$sha" --; git -C "$T_DIR" ls-files --others --exclude-standard; } | sort -u | grep -c . )"
  printf 'changed\t%s files\n' "$changed"
  if [ "$changed" -eq 0 ]; then
    printf 'summary\tnothing changed against the base\n'
    return 0
  fi

  scratch_index "$T_DIR" no || { printf 'error\t%s\tcould not copy the git index\n' "$T_NAME"; return 1; }
  printf 'begin\tsummary\n'
  # The token-savings box is the tool advertising itself; stop before it.
  crg_at "$T_DATA" "$T_DIR" detect-changes --base "$sha" --brief 2>&1 \
    | awk '/^INFO:/ {next} /^┌/ {exit} {print}'
  printf 'end\tsummary\n'
}

cmd_review() {
  local target="" given="" t failed=0
  need_crg
  while [ $# -gt 0 ]; do
    case "$1" in
      --base) [ $# -ge 2 ] || die "--base needs a ref"; given="$2"; shift 2 ;;
      -*)     die "unknown flag '$1'" ;;
      *)      [ -z "$target" ] || die "unexpected argument '$1'"; target="${1%/}"; shift ;;
    esac
  done
  [ -n "$target" ] || die "usage: graph.sh review <task>[/<repo>] [--base <ref>]"
  case "$target" in
    */*) review_one "$target" "$given" || failed=1 ;;
    *)
      [ -d "$SPACES_DIR/$target" ] || die "no space named '$target' - /space list shows what exists"
      [ -n "$(space_targets "$target")" ] || die "space '$target' has no worktrees"
      for t in $(space_targets "$target"); do
        review_one "$t" "$given" || failed=$((failed + 1))
        echo
      done ;;
  esac
  [ "$failed" -eq 0 ]
}

# ---------------------------------------------------------------------- run --

cmd_run() {
  local q
  need_crg
  [ $# -ge 2 ] || die "usage: graph.sh run <target> <query> [args...] - queries: $READ_ONLY_QUERIES"
  resolve "$1" || die "$RESOLVE_ERR"
  q="$2"; shift 2
  case " $READ_ONLY_QUERIES " in
    *" $q "*) ;;
    *) die "'$q' is not a read-only query - allowed: $READ_ONLY_QUERIES. Rebuild with graph.sh build." ;;
  esac
  [ -f "$T_DATA/built.tsv" ] || die "no graph for $T_NAME yet - graph.sh build $T_NAME"
  scratch_index "$T_DIR" no || die "could not copy the git index for $T_NAME"
  crg_at "$T_DATA" "$T_DIR" "$q" ${1+"$@"} 2>&1 | grep -v '^INFO:'
}

# ---------------------------------------------------------- drop and prune --

cmd_drop() {
  local task="${1:-}" repo="${2:-}" path
  case "$task$repo" in ""|*..*|*/*) die "usage: graph.sh drop <task> [repo]" ;; esac
  path="$GRAPHS/spaces/$task${repo:+/$repo}"
  [ -d "$path" ] || return 0
  rm -rf "$path"
  rmdir "$GRAPHS/spaces/$task" 2>/dev/null
  printf 'dropped\t%s\n' "$(rel "$path")"
}

cmd_prune() {
  local t
  for t in $(orphan_targets); do cmd_drop "${t%%/*}" "${t#*/}"; done
}

# -------------------------------------------------------------------- slash --

# /graph expands this eagerly. build and review write only derived data under
# .code-review-graph/, so they run; prune deletes, so the slash form only looks.
cmd_slash() {
  local sub="${1:-status}" t
  [ $# -gt 0 ] && shift
  # The slash result is one stream; an error row belongs in it, not lost to stderr.
  exec 2>&1
  case "$sub" in
    status)
      printf 'mode\tstatus\n'; cmd_status ;;
    build)
      if ! crg_installed; then printf 'mode\terror\nerror\tcode-review-graph is not installed - pipx install code-review-graph\n'; return; fi
      [ $# -eq 1 ] || { printf 'mode\terror\nerror\tusage: /graph build <repo> | <task>/<repo> | all\n'; return; }
      printf 'mode\tbuild\n'; cmd_build "$1" ;;
    review)
      if ! crg_installed; then printf 'mode\terror\nerror\tcode-review-graph is not installed - pipx install code-review-graph\n'; return; fi
      printf 'mode\treview\n'; cmd_review "$@" ;;
    run)
      printf 'mode\trun\n'; cmd_run "$@" ;;
    prune)
      printf 'mode\tprune\n'
      for t in $(orphan_targets); do printf 'orphan\t%s\t%s\n' "$t" "$(rel "$GRAPHS/spaces/$t")"; done ;;
    *)
      printf 'mode\terror\nerror\t%s\n' "unknown '$sub' - usage: /graph [status] | build <target>|all | review <task>[/<repo>] | run <target> <query> | prune" ;;
  esac
}

# --------------------------------------------------------------------- main --

case "${1:-}" in
  status) shift; cmd_status ;;
  build)  shift; cmd_build "$@" ;;
  review) shift; cmd_review "$@" ;;
  run)    shift; cmd_run "$@" ;;
  drop)   shift; cmd_drop "$@" ;;
  prune)  shift; cmd_prune ;;
  slash)  shift; cmd_slash ${1+"$@"} ;;
  ""|-h|--help|help) usage ;;
  *) usage; exit 2 ;;
esac
