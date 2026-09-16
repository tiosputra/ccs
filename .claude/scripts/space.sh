#!/usr/bin/env bash
#
# space.sh - create/list/remove a multi-repo "space" of git worktrees.
#
# A space is one task (feature/bugfix/hotfix) checked out across several
# services at once:
#
#   spaces/<task>/<repo>   <- worktree, on branch <prefix>/<task>
#
# Usage:
#   space.sh add <task> [repos] [--from <ref>] [--branch <name>]
#                               [--no-fetch] [--no-env] [--dry-run]
#   space.sh list [task]
#   space.sh repos                  the roster, read from disk
#   space.sh config                 resolved settings and where they came from
#   space.sh report <task>          facts for a wrap-up summary (read-only)
#   space.sh remove <task> [repos] [--delete-branch] [--force]
#   space.sh slash <args...>        dispatcher for the /space command
#
#   Repos named in REFERENCE_REPOS (.env, comma list) are read-only: they get
#   no worktree, and the guard hook refuses writes to them anywhere. They are
#   there to be read and asked about, not worked on.
#
#   repos   comma list of aliases - `space.sh repos` lists them. Default:
#           every checkout except the reference-only ones.
#   --from  base ref for NEW branches. Either one ref for everything
#           (--from origin/main) or per-repo overrides
#           (--from backend=origin/release-2,sport=origin/main).
#           Default: origin/main.
#
# Examples:
#   space.sh add fix-promo backend,player --from origin/feature/m5.1
#   space.sh add feature-booking --from origin/develop
#   space.sh add hotfix-payment backend --from backend=origin/release-2
#   space.sh remove fix-promo --delete-branch

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPOS_DIR="$ROOT/repos"
SPACES_DIR="$ROOT/spaces"
DOCS_DIR="$ROOT/docs"

. "$SCRIPT_DIR/config.sh"
cfg_resolve SPACE_BRANCH_PREFIX ccs
cfg_resolve SPACE_DEFAULT_BASE origin/main
cfg_resolve REFERENCE_REPOS ""
BRANCH_PREFIX="$SPACE_BRANCH_PREFIX"
DEFAULT_BASE="$SPACE_DEFAULT_BASE"
# Untracked-but-essential files copied from the main checkout into a new
# worktree (git worktrees only carry tracked files).
ENV_GLOBS=(".env" ".env.local" ".env.development" ".env.*.local")

# ---------------------------------------------------------------- output --

if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""
fi

info() { printf '%s\n' "$*"; }
step() { printf '%s==>%s %s\n' "$C_BLUE$C_BOLD" "$C_RESET" "$*"; }
ok()   { printf '  %s+%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
skip() { printf '  %s=%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
warn() { printf '  %s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
fail() { printf '  %sx%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
dim()  { printf '    %s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }
die()  { printf '%serror:%s %s\n' "$C_RED$C_BOLD" "$C_RESET" "$*" >&2; exit 1; }

usage() { sed -n '3,35p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# ----------------------------------------------------------------- repos --

# All repo dir names under repos/ that are git checkouts.
all_repos() {
  local d
  for d in "$REPOS_DIR"/*/; do
    [ -e "$d/.git" ] || continue
    basename "$d"
  done
}

# Repos kept for reference only - read, search, ask questions, never edit.
# REFERENCE_REPOS is a comma list of aliases; guard.sh reads the same setting
# and seals both repos/<repo> and spaces/<task>/<repo>.
is_reference_repo() {
  local want="$1" list
  list=",${REFERENCE_REPOS//[[:space:]]/},"
  case "$list" in *",$want,"*) return 0 ;; esac
  return 1
}

# The repos a space may actually open a worktree for.
workable_repos() {
  local r
  for r in $(all_repos); do
    is_reference_repo "$r" || printf '%s\n' "$r"
  done
}

# backend -> backend | sport-service -> sport | player-service -> player
resolve_repo() {
  local want="$1" r
  for r in $(all_repos); do
    [ "$r" = "$want" ] && { printf '%s' "$r"; return 0; }
  done
  # tolerate the full service name: sport-service, player-service
  for r in $(all_repos); do
    case "$want" in "$r"-*|"$r"_*) printf '%s' "$r"; return 0;; esac
  done
  return 1
}

# comma list -> validated repo dir names, one per line
parse_repos() {
  local csv="$1" want resolved out="" parts
  IFS=',' read -r -a parts <<<"$csv"
  for want in "${parts[@]}"; do
    want="${want//[[:space:]]/}"
    [ -n "$want" ] || continue
    if ! resolved="$(resolve_repo "$want")"; then
      die "unknown repo '$want'. Available: $(workable_repos | paste -sd, -)"
    fi
    if is_reference_repo "$resolved"; then
      die "'$resolved' is reference-only (REFERENCE_REPOS in .env) - it is there to be read, not worked on. Drop it from REFERENCE_REPOS if that has changed."
    fi
    case " $out " in *" $resolved "*) continue;; esac
    out="$out $resolved"
  done
  printf '%s\n' $out
}

# --------------------------------------------------------------- helpers --

# --from value -> BASE_DEFAULT plus per-repo overrides.
# Kept as a newline-separated "repo<TAB>ref" list, not an associative array,
# because macOS still ships bash 3.2.
BASE_OVERRIDES=""
BASE_DEFAULT="$DEFAULT_BASE"
parse_from() {
  local spec="$1" part key val resolved
  IFS=',' read -r -a parts <<<"$spec"
  for part in "${parts[@]}"; do
    part="${part//[[:space:]]/}"
    [ -n "$part" ] || continue
    if [[ "$part" == *=* ]]; then
      key="${part%%=*}"; val="${part#*=}"
      resolved="$(resolve_repo "$key")" || die "--from: unknown repo '$key'"
      BASE_OVERRIDES="$BASE_OVERRIDES$resolved	$val
"
    else
      BASE_DEFAULT="$part"
    fi
  done
}

base_for() {
  local repo="$1" key val
  while IFS='	' read -r key val; do
    [ "$key" = "$repo" ] && { printf '%s' "$val"; return 0; }
  done <<<"$BASE_OVERRIDES"
  printf '%s' "$BASE_DEFAULT"
}

copy_env_files() {
  local src="$1" dst="$2" glob f n=0
  for glob in "${ENV_GLOBS[@]}"; do
    for f in "$src"/$glob; do
      [ -f "$f" ] || continue
      cp -p "$f" "$dst/$(basename "$f")"
      n=$((n + 1))
    done
  done
  [ "$n" -gt 0 ] && dim "copied $n env file(s) from repos/$(basename "$src")"
  return 0
}

# ------------------------------------------------------------------- new --

cmd_new() {
  local task="" repos_csv="" branch="" do_fetch=1 do_env=1 dry=0 from_spec=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --from)   from_spec="${2:-}"; shift 2 ;;
      --from=*) from_spec="${1#*=}"; shift ;;
      --branch)   branch="${2:-}"; shift 2 ;;
      --branch=*) branch="${1#*=}"; shift ;;
      --no-fetch) do_fetch=0; shift ;;
      --no-env)   do_env=0; shift ;;
      --dry-run)  dry=1; shift ;;
      -h|--help)  usage; return 0 ;;
      -*) die "unknown flag '$1'" ;;
      *)
        if   [ -z "$task" ];      then task="$1"
        elif [ -z "$repos_csv" ]; then repos_csv="$1"
        else die "unexpected argument '$1'"
        fi
        shift ;;
    esac
  done

  [ -n "$task" ] || { usage; die "missing <task>"; }
  [ -n "$from_spec" ] && parse_from "$from_spec"
  [ -n "$branch" ] || branch="$BRANCH_PREFIX/$task"

  local repos
  if [ -n "$repos_csv" ]; then
    repos="$(parse_repos "$repos_csv")"
  else
    repos="$(workable_repos)"
  fi
  [ -n "$repos" ] || die "no workable repos found under $REPOS_DIR"

  local space="$SPACES_DIR/$task"
  step "space ${C_BOLD}$task${C_RESET}  branch ${C_BOLD}$branch${C_RESET}"
  info "    ${C_DIM}$space${C_RESET}"
  [ "$dry" -eq 1 ] && info "    ${C_YELLOW}dry run - nothing will be written${C_RESET}"

  # A little metadata so `report` can state the true base ref later, once
  # the branch has moved on and the base is no longer inferable.
  local meta="$space/.space"
  if [ "$dry" -eq 0 ]; then
    mkdir -p "$space"
    if [ ! -f "$meta" ]; then
      {
        printf 'task\t%s\n' "$task"
        printf 'branch\t%s\n' "$branch"
        printf 'created\t%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
      } >"$meta"
    fi
  fi

  local repo dir wt base failed=0 made=0
  for repo in $repos; do
    dir="$REPOS_DIR/$repo"
    wt="$space/$repo"
    base="$(base_for "$repo")"

    if [ -e "$wt" ]; then
      skip "$repo  worktree already exists"
      continue
    fi

    # Reuse the branch if it already exists locally or on origin, so a
    # second repo (or a re-run) joins the same branch instead of erroring.
    local add_args=()
    if git -C "$dir" show-ref --verify --quiet "refs/heads/$branch"; then
      add_args=("$wt" "$branch")
      dim "$repo  reusing existing local branch"
    else
      if [ "$do_fetch" -eq 1 ]; then
        if ! git -C "$dir" fetch --prune --quiet origin 2>/dev/null; then
          warn "$repo  fetch failed, using local refs"
        fi
      fi
      if git -C "$dir" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
        add_args=("$wt" --track -b "$branch" "origin/$branch")
        dim "$repo  tracking existing origin/$branch"
      else
        if ! git -C "$dir" rev-parse --verify --quiet "$base^{commit}" >/dev/null; then
          fail "$repo  base ref '$base' not found"
          failed=$((failed + 1))
          continue
        fi
        add_args=("$wt" -b "$branch" "$base")
      fi
    fi

    if [ "$dry" -eq 1 ]; then
      ok "$repo  git -C repos/$repo worktree add ${add_args[*]}"
      made=$((made + 1))
      continue
    fi

    if git -C "$dir" worktree add "${add_args[@]}" >/dev/null 2>&1; then
      ok "$repo  ${C_DIM}$(git -C "$wt" rev-parse --short HEAD) from $base${C_RESET}"
      printf 'base\t%s\t%s\t%s\n' \
        "$repo" "$base" "$(git -C "$wt" rev-parse HEAD)" >>"$meta"
      [ "$do_env" -eq 1 ] && copy_env_files "$dir" "$wt"
      made=$((made + 1))
    else
      fail "$repo  worktree add failed"
      git -C "$dir" worktree add "${add_args[@]}" 2>&1 | sed 's/^/      /' >&2 || true
      failed=$((failed + 1))
    fi
  done

  info ""
  if [ "$failed" -gt 0 ]; then
    info "${C_RED}$failed repo(s) failed${C_RESET}, $made ready"
    return 1
  fi
  info "${C_GREEN}ready${C_RESET}  cd $space"
}

# ----------------------------------------------------------------- repos --

# The roster, read from disk. Docs point at this instead of naming services,
# so cloning another checkout into repos/ never needs a doc edit.
cmd_repos() {
  local repo dir url open note n=0 refs=0
  [ -d "$REPOS_DIR" ] || { info "no repos yet"; return 0; }
  step "repos"
  for repo in $(all_repos); do
    dir="$REPOS_DIR/$repo"
    url="$(git -C "$dir" remote get-url origin 2>/dev/null || echo '-')"
    # git@github.com:Org/name.git and https://github.com/Org/name -> Org/name
    url="$(printf '%s' "$url" | sed -e 's|\.git$||' -e 's|^.*github\.com[:/]||')"
    open=""
    for d in "$SPACES_DIR"/*/"$repo"; do
      [ -e "$d/.git" ] || continue
      open="$open $(basename "$(dirname "$d")")"
    done
    if is_reference_repo "$repo"; then
      note="${C_YELLOW}reference-only${C_RESET}"
      refs=$((refs + 1))
    else
      note="${open:+open:${open// /, }}"
    fi
    printf '  %-10s %-16s %-34s %s\n' \
      "$repo" "repos/$repo" "$url" "$note"
    n=$((n + 1))
  done
  info ""
  info "$n checkout(s). The directory name is the alias; a longer service name"
  info "resolves by prefix, so 'sport-service' finds 'sport'."
  info "Add one by cloning into repos/ - nothing else needs changing."
  if [ "$refs" -gt 0 ]; then
    info ""
    info "$refs reference-only (REFERENCE_REPOS in .env): read them, ask about"
    info "them, never edit them. They get no worktree and the guard refuses"
    info "writes to them everywhere."
  fi
}

# ---------------------------------------------------------------- config --

# What the settings actually resolved to, and which layer won. Docs state the
# rule; this states the value, so no tracked file has to name anyone's prefix.
cmd_config() {
  step "config"
  printf '  %-22s %-18s %s\n' "SPACE_BRANCH_PREFIX" "$BRANCH_PREFIX" \
    "(from $(cfg_source SPACE_BRANCH_PREFIX))"
  printf '  %-22s %-18s %s\n' "SPACE_DEFAULT_BASE" "$DEFAULT_BASE" \
    "(from $(cfg_source SPACE_DEFAULT_BASE))"
  printf '  %-22s %-18s %s\n' "REFERENCE_REPOS" "${REFERENCE_REPOS:--}" \
    "(from $(cfg_source REFERENCE_REPOS))"
  info ""
  info "  a new space would branch:  ${C_BOLD}$BRANCH_PREFIX/<task>${C_RESET}"
  if [ -n "$REFERENCE_REPOS" ]; then
    info "  read-only everywhere:      ${C_BOLD}${REFERENCE_REPOS}${C_RESET}"
  fi
  info ""
  if [ -f "$(cfg_file)" ]; then
    dim "$(cfg_file) exists (gitignored)"
  else
    dim "no .env yet - cp .env.example .env to set your own"
  fi
}

# ------------------------------------------------------------------ list --

cmd_list() {
  local only="${1:-}"
  [ -d "$SPACES_DIR" ] || { info "no spaces yet"; return 0; }

  local space task repo wt branch dirty found=0
  for space in "$SPACES_DIR"/*/; do
    [ -d "$space" ] || continue
    task="$(basename "$space")"
    [ -n "$only" ] && [ "$task" != "$only" ] && continue
    found=1
    step "$task"
    for wt in "$space"/*/; do
      [ -e "$wt/.git" ] || continue
      repo="$(basename "$wt")"
      branch="$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
      if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then
        dirty="${C_YELLOW}dirty${C_RESET}"
      else
        dirty="${C_DIM}clean${C_RESET}"
      fi
      printf '  %-10s %-28s %s\n' "$repo" "$branch" "$dirty"
    done
  done
  [ "$found" -eq 1 ] || info "no spaces yet"
}

# ---------------------------------------------------------------- report --

# Everything needed to write a wrap-up summary, gathered while the worktrees
# still exist. Read-only: never mutates anything.
cmd_report() {
  local task="${1:-}"
  [ -n "$task" ] || die "missing <task>"
  local space="$SPACES_DIR/$task"
  [ -d "$space" ] || die "no such space: $space"
  local meta="$space/.space"

  printf 'space\t%s\n' "$task"
  printf 'path\t%s\n' "$space"
  printf 'today\t%s\n' "$(date '+%Y-%m-%d')"

  # Where this task's docs live: docs/<YYYY-MM-DD>_<task>/. The date is the day
  # the task opened, so it cannot be derived - it is globbed. `-` means the task
  # never had a PRD, and whoever writes the log creates the directory.
  local d docdir=""
  for d in "$DOCS_DIR"/*_"$task"/; do
    [ -d "$d" ] || continue
    docdir="${d#$ROOT/}"; docdir="${docdir%/}"
    break
  done
  printf 'docs\t%s\n' "${docdir:--}"
  if [ -f "$meta" ]; then
    grep -E '^(branch|created)	' "$meta" || true
  fi

  local wt repo branch base base_sha head upstream ahead behind unpushed dirty
  for wt in "$space"/*/; do
    [ -e "$wt/.git" ] || continue
    repo="$(basename "$wt")"
    branch="$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
    head="$(git -C "$wt" rev-parse --short HEAD 2>/dev/null || echo '?')"

    base=""; base_sha=""
    if [ -f "$meta" ]; then
      base="$(awk -F'\t' -v r="$repo" '$1=="base" && $2==r {print $3}' "$meta")"
      base_sha="$(awk -F'\t' -v r="$repo" '$1=="base" && $2==r {print $4}' "$meta")"
    fi
    # Spaces made before metadata existed: fall back to the fork point.
    if [ -z "$base_sha" ]; then
      base_sha="$(git -C "$wt" merge-base HEAD origin/main 2>/dev/null || echo '')"
      [ -n "$base_sha" ] && base="${base:-origin/main (inferred)}"
    fi

    printf '\nrepo\t%s\n' "$repo"
    printf 'branch\t%s\n' "$branch"
    printf 'base\t%s\t%s\n' "${base:-unknown}" "$(printf '%.9s' "${base_sha:-unknown}")"
    printf 'head\t%s\n' "$head"

    dirty="$(git -C "$wt" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    printf 'uncommitted\t%s\n' "$dirty"

    upstream="$(git -C "$wt" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || echo 'none')"
    printf 'upstream\t%s\n' "$upstream"
    if [ "$upstream" != "none" ]; then
      ahead="$(git -C "$wt" rev-list --count "$upstream"..HEAD 2>/dev/null || echo 0)"
      behind="$(git -C "$wt" rev-list --count HEAD.."$upstream" 2>/dev/null || echo 0)"
      printf 'ahead\t%s\nbehind\t%s\n' "$ahead" "$behind"
    fi
    # Commits that exist on no remote at all - these die with the branch.
    unpushed="$(git -C "$wt" rev-list --count HEAD --not --remotes 2>/dev/null || echo 0)"
    printf 'unpushed\t%s\n' "$unpushed"

    if [ -n "$base_sha" ]; then
      printf 'commits\t%s\n' "$(git -C "$wt" rev-list --count "$base_sha"..HEAD 2>/dev/null || echo 0)"
      git -C "$wt" log --no-merges --format='log	%h	%an	%ad	%s' \
        --date=short "$base_sha"..HEAD 2>/dev/null || true
      git -C "$wt" diff --shortstat "$base_sha"..HEAD 2>/dev/null \
        | sed 's/^ */diffstat\t/' || true
      git -C "$wt" diff --name-status "$base_sha"..HEAD 2>/dev/null \
        | sed 's/^/file\t/' || true
    fi
  done
}

# -------------------------------------------------------------------- rm --

cmd_rm() {
  local task="" repos_csv="" del_branch=0 force=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --delete-branch|-d) del_branch=1; shift ;;
      --force|-f)         force=1; shift ;;
      -h|--help)          usage; return 0 ;;
      -*) die "unknown flag '$1'" ;;
      *)
        if   [ -z "$task" ];      then task="$1"
        elif [ -z "$repos_csv" ]; then repos_csv="$1"
        else die "unexpected argument '$1'"
        fi
        shift ;;
    esac
  done

  [ -n "$task" ] || die "missing <task>"
  local space="$SPACES_DIR/$task"
  [ -d "$space" ] || die "no such space: $space"

  local repos
  if [ -n "$repos_csv" ]; then repos="$(parse_repos "$repos_csv")"; else repos="$(workable_repos)"; fi

  step "removing space ${C_BOLD}$task${C_RESET}"
  local repo dir wt branch rm_args failed=0

  # Check every repo before touching any, so a blocked removal leaves the
  # whole space intact instead of half torn down.
  if [ "$force" -eq 0 ]; then
    local blocked=0
    for repo in $repos; do
      wt="$space/$repo"
      [ -e "$wt" ] || continue
      if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then
        fail "$repo  has uncommitted changes"
        blocked=$((blocked + 1))
      fi
      # Deleting the branch discards commits that reached no remote.
      if [ "$del_branch" -eq 1 ]; then
        local unpushed
        unpushed="$(git -C "$wt" rev-list --count HEAD --not --remotes 2>/dev/null || echo 0)"
        if [ "$unpushed" -gt 0 ]; then
          fail "$repo  $unpushed commit(s) not pushed to any remote"
          blocked=$((blocked + 1))
        fi
      fi
    done
    if [ "$blocked" -gt 0 ]; then
      info ""
      info "nothing removed. Push or stash that work, or re-run with --force to discard it."
      return 1
    fi
  fi

  for repo in $repos; do
    dir="$REPOS_DIR/$repo"
    wt="$space/$repo"
    [ -e "$wt" ] || continue

    branch="$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"

    rm_args=(worktree remove "$wt")
    [ "$force" -eq 1 ] && rm_args=(worktree remove --force "$wt")
    if git -C "$dir" "${rm_args[@]}" >/dev/null 2>&1; then
      ok "$repo  worktree removed"
      # Its code-review-graph data describes a worktree that no longer exists.
      if [ -x "$SCRIPT_DIR/graph.sh" ] && [ -n "$("$SCRIPT_DIR/graph.sh" drop "$task" "$repo" 2>/dev/null)" ]; then
        dim "$repo  dropped its code-review-graph data"
      fi
    else
      fail "$repo  worktree remove failed"
      failed=$((failed + 1))
      continue
    fi

    if [ "$del_branch" -eq 1 ] && [ -n "$branch" ]; then
      if git -C "$dir" branch -D "$branch" >/dev/null 2>&1; then
        dim "$repo  deleted branch $branch (local only)"
      else
        warn "$repo  could not delete branch $branch"
      fi
    fi
  done

  # Drop the metadata only once nothing is left that might still need it.
  if [ -z "$(find "$space" -mindepth 1 -maxdepth 1 -not -name '.space' 2>/dev/null)" ]; then
    rm -f "$space/.space"
    rmdir "$space" 2>/dev/null && dim "removed $space" || true
  fi
  [ "$failed" -eq 0 ] || return 1
}

# ----------------------------------------------------------------- slash --

# Entry point for the /space slash command, which expands this eagerly - so
# it must not remove anything on its own. `add` and `list` run for real;
# `remove` answers with the read-only report instead, and the teardown
# happens only after the wrap-up log has been written.
cmd_slash() {
  local sub="${1:-}"
  case "$sub" in
    add|new)
      shift
      printf 'mode\tadd\n\n'
      cmd_new "$@"
      ;;
    remove|rm)
      shift
      local task="" force=0 arg
      for arg in "$@"; do
        case "$arg" in
          --force|-f) force=1 ;;
          -*) ;;
          *) [ -n "$task" ] || task="$arg" ;;
        esac
      done
      printf 'mode\tremove\nforce\t%s\n\n' "$force"
      cmd_report "$task"
      ;;
    list|ls)
      shift
      printf 'mode\tlist\n\n'
      cmd_list "$@"
      ;;
    repos)
      shift
      printf 'mode\trepos\n\n'
      cmd_repos
      ;;
    config)
      shift
      printf 'mode\tconfig\n\n'
      cmd_config
      ;;
    ""|-h|--help)
      usage
      ;;
    *)
      usage
      die "unknown command '$sub' - use add, remove, list, repos, or config"
      ;;
  esac
}

# ------------------------------------------------------------------ main --

[ -d "$REPOS_DIR" ] || die "repos dir not found: $REPOS_DIR"

case "${1:-}" in
  ""|-h|--help) usage ;;
  add|new)   shift; cmd_new "$@" ;;
  list|ls)   shift; cmd_list "$@" ;;
  repos)     shift; cmd_repos ;;
  config)    shift; cmd_config ;;
  report)    shift; cmd_report "$@" ;;
  remove|rm) shift; cmd_rm "$@" ;;
  slash)     shift; cmd_slash "$@" ;;
  *) usage; die "unknown command '$1' - use add, remove, list, repos, or config" ;;
esac
