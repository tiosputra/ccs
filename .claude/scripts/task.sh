#!/usr/bin/env bash
#
# task.sh - start, find, report on and finish a task across one or more repos.
#
# A task is one feature, bugfix or hotfix, on one branch - <prefix>/<task> -
# in every repo it touches. Where that branch is worked on is the task's
# isolation, chosen at start and fixed after (see tasklib.sh):
#
#   inplace   repos/<repo>                the default
#   space     spaces/<task>/<repo>        a worktree per repo, opt in with --space
#
# Usage:
#   task.sh start <task> [repos] [--from <ref>] [--space|--inplace]
#                                [--branch <name>] [--no-fetch] [--no-env] [--dry-run]
#   task.sh where <task> [repo]     working directory, or repo<TAB>dir per repo
#   task.sh root                    the workspace root, absolute
#   task.sh list [task]             open tasks and the state of each repo
#   task.sh report <task>           facts for a wrap-up summary (read-only)
#   task.sh repos                   the roster, read from disk
#   task.sh config                  resolved settings and where they came from
#   task.sh finish <task> [repos] [--delete-branch] [--force]
#   task.sh slash <args...>         dispatcher for the /task command
#
#   Repos named in REFERENCE_REPOS (.env, comma list) are read-only: a task
#   never includes them, and the guard hook refuses writes to them anywhere.
#
#   repos   comma list of aliases - `task.sh repos` lists them. Default: every
#           checkout except the reference-only ones.
#   --from  base ref for NEW branches. One ref for everything (--from
#           origin/main) or per-repo overrides (--from api=origin/release-2,
#           web=origin/main). Default: TASK_DEFAULT_BASE.
#   --space / --inplace   the task's isolation. Default: TASK_DEFAULT_ISOLATION.
#
# Examples:
#   task.sh start fix-promo api,web --from origin/feature/m5.1
#   task.sh start rework-booking --from origin/develop --space
#   task.sh where fix-promo api
#   task.sh finish fix-promo --delete-branch

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPOS_DIR="$ROOT/repos"
SPACES_DIR="$ROOT/spaces"
DOCS_DIR="$ROOT/docs"

. "$SCRIPT_DIR/config.sh"
. "$SCRIPT_DIR/tasklib.sh"
cfg_resolve_renamed TASK_BRANCH_PREFIX SPACE_BRANCH_PREFIX ccs
cfg_resolve_renamed TASK_DEFAULT_BASE SPACE_DEFAULT_BASE origin/main
cfg_resolve TASK_DEFAULT_ISOLATION inplace
cfg_resolve REFERENCE_REPOS ""
BRANCH_PREFIX="$TASK_BRANCH_PREFIX"
DEFAULT_BASE="$TASK_DEFAULT_BASE"
DEFAULT_ISOLATION="$TASK_DEFAULT_ISOLATION"
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

usage() { sed -n '3,38p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

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
# and seals them in repos/ and in every space.
is_reference_repo() {
  local want="$1" list
  list=",${REFERENCE_REPOS//[[:space:]]/},"
  case "$list" in *",$want,"*) return 0 ;; esac
  return 1
}

# The repos a task may actually work in.
workable_repos() {
  local r
  for r in $(all_repos); do
    is_reference_repo "$r" || printf '%s\n' "$r"
  done
}

# An exact alias, or a longer service name that starts with one:
# api -> api, api-service -> api.
resolve_repo() {
  local want="$1" r
  for r in $(all_repos); do
    [ "$r" = "$want" ] && { printf '%s' "$r"; return 0; }
  done
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
  local spec="$1" part key val resolved parts
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

rel() { printf '%s\n' "${1#"$ROOT"/}"; }

# Write the task's metadata once; later starts only append base lines.
write_meta() {
  local task="$1" isolation="$2" branch="$3" meta="$TL_STATE/$1"
  mkdir -p "$TL_STATE"
  [ -f "$meta" ] && return 0
  {
    printf 'task\t%s\n' "$task"
    printf 'isolation\t%s\n' "$isolation"
    printf 'branch\t%s\n' "$branch"
    printf 'created\t%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  } >"$meta"
}

# The commit a repo's task work is measured from: where the task branch left
# <ref>. For a new branch that is HEAD; for a reused one - a re-join for review
# fixes - it is the merge-base, so the task's earlier commits still count.
base_sha() {
  git -C "$1" merge-base HEAD "$2" 2>/dev/null || git -C "$1" rev-parse HEAD
}

# record_base <task> <repo> <ref> <sha> - a repo has joined the task. The
# metadata is written with the first repo that actually joins, never before,
# so a start that fails everywhere leaves nothing behind. A task that already
# has metadata - current, or a legacy spaces/<task>/.space - gets a line added.
START_ISOLATION="" START_BRANCH=""
record_base() {
  local meta
  meta="$(task_meta "$1" 2>/dev/null)" || {
    write_meta "$1" "$START_ISOLATION" "$START_BRANCH"
    meta="$TL_STATE/$1"
  }
  printf 'base\t%s\t%s\t%s\n' "$2" "$3" "$4" >>"$meta"
}

# ----------------------------------------------------------------- start --

# The branch a repo joins the task on, and how: prints the `git worktree add`
# / `git switch` arguments after the path, or fails with a reason.
start_args() {
  local dir="$1" branch="$2" base="$3" do_fetch="$4"
  if git -C "$dir" show-ref --verify --quiet "refs/heads/$branch"; then
    printf 'existing\t%s\n' "$branch"
    return 0
  fi
  if [ "$do_fetch" -eq 1 ]; then
    git -C "$dir" fetch --prune --quiet origin 2>/dev/null || warn "$(basename "$dir")  fetch failed, using local refs"
  fi
  if git -C "$dir" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    printf 'track\torigin/%s\n' "$branch"
    return 0
  fi
  git -C "$dir" rev-parse --verify --quiet "$base^{commit}" >/dev/null || return 1
  printf 'new\t%s\n' "$base"
}

start_space_repo() {
  local task="$1" repo="$2" branch="$3" base="$4" do_fetch="$5" do_env="$6" dry="$7"
  local dir="$REPOS_DIR/$repo" wt="$SPACES_DIR/$task/$repo" how from add_args=()

  if [ -e "$wt" ]; then
    skip "$repo  worktree already exists"
    return 0
  fi
  how="$(start_args "$dir" "$branch" "$base" "$do_fetch")" \
    || { fail "$repo  base ref '$base' not found"; return 1; }
  from="${how#*	}"
  case "${how%%	*}" in
    existing) add_args=("$wt" "$branch"); dim "$repo  reusing existing local branch" ;;
    track)    add_args=("$wt" --track -b "$branch" "$from"); dim "$repo  tracking existing $from" ;;
    new)      add_args=("$wt" -b "$branch" "$from") ;;
  esac

  if [ "$dry" -eq 1 ]; then
    ok "$repo  git -C repos/$repo worktree add ${add_args[*]}"
    return 0
  fi
  mkdir -p "$SPACES_DIR/$task"
  if git -C "$dir" worktree add "${add_args[@]}" >/dev/null 2>&1; then
    ok "$repo  ${C_DIM}$(git -C "$wt" rev-parse --short HEAD) from $base${C_RESET}"
    record_base "$task" "$repo" "$base" "$(base_sha "$wt" "$base")"
    [ "$do_env" -eq 1 ] && copy_env_files "$dir" "$wt"
    return 0
  fi
  fail "$repo  worktree add failed"
  git -C "$dir" worktree add "${add_args[@]}" 2>&1 | sed 's/^/      /' >&2 || true
  return 1
}

# The branch a checkout is on, or its commit when detached.
checkout_head() {
  git -C "$1" symbolic-ref --short -q HEAD 2>/dev/null || git -C "$1" rev-parse HEAD
}

# In place: the repo's own checkout switches to the task branch. A checkout is
# busy when another in-place task holds it, or when it has uncommitted work -
# switching would carry that work onto this task's branch. Busy is refused and
# pointed at --space; the task's layout is never changed here.
start_inplace_repo() {
  local task="$1" repo="$2" branch="$3" base="$4" do_fetch="$5" dry="$6"
  local dir="$REPOS_DIR/$repo" holder cur how from sw=()

  if holder="$(task_holding "$repo")" && [ "$holder" != "$task" ]; then
    fail "$repo  held in place by task '$holder' - one in-place task per repo; start this one with --space"
    return 1
  fi
  cur="$(checkout_head "$dir")"
  if [ "$cur" = "$branch" ] && task_has_repo "$task" "$repo"; then
    skip "$repo  already on $branch"
    return 0
  fi
  if [ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]; then
    fail "$repo  repos/$repo has uncommitted changes - clean it, or start this task with --space"
    return 1
  fi

  how="$(start_args "$dir" "$branch" "$base" "$do_fetch")" \
    || { fail "$repo  base ref '$base' not found"; return 1; }
  from="${how#*	}"
  case "${how%%	*}" in
    existing) sw=("$branch"); dim "$repo  reusing existing local branch" ;;
    track)    sw=(--track -c "$branch" "$from"); dim "$repo  tracking existing $from" ;;
    new)      sw=(-c "$branch" "$from") ;;
  esac

  if [ "$dry" -eq 1 ]; then
    ok "$repo  git -C repos/$repo switch ${sw[*]}   (from $cur)"
    return 0
  fi
  if ! git -C "$dir" switch -q "${sw[@]}" 2>/dev/null; then
    fail "$repo  switch to $branch failed"
    git -C "$dir" switch "${sw[@]}" 2>&1 | sed 's/^/      /' >&2 || true
    return 1
  fi
  # A repo already in the task was moved off its branch and is being put back:
  # its base and home are recorded from the first time it joined.
  if ! task_has_repo "$task" "$repo"; then
    record_base "$task" "$repo" "$base" "$(base_sha "$dir" "$base")"
    # Where the checkout was, so finish can put it back.
    printf 'home\t%s\t%s\n' "$repo" "$cur" >>"$(task_meta "$task")"
  fi
  ok "$repo  ${C_DIM}$(git -C "$dir" rev-parse --short HEAD) from $base, repos/$repo was on $cur${C_RESET}"
}

cmd_start() {
  local task="" repos_csv="" branch="" do_fetch=1 do_env=1 dry=0 from_spec="" isolation=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --from)   from_spec="${2:-}"; shift 2 ;;
      --from=*) from_spec="${1#*=}"; shift ;;
      --branch)   branch="${2:-}"; shift 2 ;;
      --branch=*) branch="${1#*=}"; shift ;;
      --space)    isolation=space; shift ;;
      --inplace|--in-place) isolation=inplace; shift ;;
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
  case "$task" in *[!a-z0-9-]*|-*) die "task names are kebab-case: '$task'" ;; esac
  [ -n "$from_spec" ] && parse_from "$from_spec"

  # One isolation per task, fixed at its first start.
  if task_exists "$task"; then
    local have; have="$(task_isolation "$task")"
    [ -z "$isolation" ] || [ "$isolation" = "$have" ] \
      || die "task '$task' already works $have - a task has one isolation for every repo"
    isolation="$have"
    [ -n "$branch" ] || branch="$(task_branch "$task")"
  fi
  [ -n "$isolation" ] || isolation="$DEFAULT_ISOLATION"
  case "$isolation" in inplace|space) ;; *) die "TASK_DEFAULT_ISOLATION must be inplace or space, not '$isolation'" ;; esac
  [ -n "$branch" ] || branch="$BRANCH_PREFIX/$task"

  local repos
  if [ -n "$repos_csv" ]; then
    repos="$(parse_repos "$repos_csv")"
  else
    repos="$(workable_repos)"
  fi
  [ -n "$repos" ] || die "no workable repos found under $REPOS_DIR"

  step "task ${C_BOLD}$task${C_RESET}  $isolation  branch ${C_BOLD}$branch${C_RESET}"
  [ "$dry" -eq 1 ] && info "    ${C_YELLOW}dry run - nothing will be written${C_RESET}"
  START_ISOLATION="$isolation" START_BRANCH="$branch"

  local repo failed=0 made=0
  for repo in $repos; do
    if [ "$isolation" = space ]; then
      start_space_repo "$task" "$repo" "$branch" "$(base_for "$repo")" "$do_fetch" "$do_env" "$dry" \
        && made=$((made + 1)) || failed=$((failed + 1))
    else
      start_inplace_repo "$task" "$repo" "$branch" "$(base_for "$repo")" "$do_fetch" "$dry" \
        && made=$((made + 1)) || failed=$((failed + 1))
    fi
  done

  info ""
  if [ "$failed" -gt 0 ]; then
    info "${C_RED}$failed repo(s) failed${C_RESET}, $made ready"
    return 1
  fi
  [ "$dry" -eq 1 ] && return 0
  info "${C_GREEN}ready${C_RESET}"
  for repo in $repos; do dim "$repo  $(task_workdir "$task" "$repo")"; done
}

# ----------------------------------------------------------------- where --

# The one question everything else asks. With a repo: its working directory.
# Without: repo<TAB>dir for every repo in the task.
cmd_where() {
  local task="${1:-}" repo="${2:-}" r
  [ -n "$task" ] || die "usage: task.sh where <task> [repo]"
  task_exists "$task" || die "no task named '$task' - task.sh list shows what is open"
  if [ -n "$repo" ]; then
    task_has_repo "$task" "$repo" \
      || die "'$repo' is not in task '$task' - it has: $(task_repos "$task" | paste -sd, -). Add it with task.sh start $task $repo"
    task_workdir "$task" "$repo"
    return 0
  fi
  for r in $(task_repos "$task"); do
    printf '%s\t%s\n' "$r" "$(task_workdir "$task" "$r")"
  done
}

# ----------------------------------------------------------------- repos --

# The roster, read from disk. Docs point at this instead of naming services,
# so cloning another checkout into repos/ never needs a doc edit.
cmd_repos() {
  local repo dir url open note n=0 refs=0 t
  [ -d "$REPOS_DIR" ] || { info "no repos yet"; return 0; }
  step "repos"
  for repo in $(all_repos); do
    dir="$REPOS_DIR/$repo"
    url="$(git -C "$dir" remote get-url origin 2>/dev/null || echo '-')"
    # git@github.com:Org/name.git and https://github.com/Org/name -> Org/name
    url="$(printf '%s' "$url" | sed -e 's|\.git$||' -e 's|^.*github\.com[:/]||')"
    open=""
    for t in $(task_names); do
      task_has_repo "$t" "$repo" && open="$open $t($(task_isolation "$t"))"
    done
    open="${open# }"
    if is_reference_repo "$repo"; then
      note="${C_YELLOW}reference-only${C_RESET}"
      refs=$((refs + 1))
    else
      note="${open:+open:${open// /, }}"
    fi
    printf '  %-12s %-34s %s\n' "$repo" "$url" "$note"
    n=$((n + 1))
  done
  info ""
  info "$n checkout(s) under repos/. The directory name is the alias; a longer"
  info "service name resolves by prefix, so 'api-service' finds 'api'."
  info "Add one by cloning into repos/ - nothing else needs changing."
  if [ "$refs" -gt 0 ]; then
    info ""
    info "$refs reference-only (REFERENCE_REPOS in .env): read them, ask about"
    info "them, never edit them. No task includes them and the guard refuses"
    info "writes to them everywhere."
  fi
}

# ---------------------------------------------------------------- config --

# What the settings actually resolved to, and which layer won. Docs state the
# rule; this states the value, so no tracked file has to name anyone's prefix.
cmd_config() {
  step "config"
  printf '  %-24s %-16s %s\n' "TASK_BRANCH_PREFIX" "$BRANCH_PREFIX" \
    "(from $(cfg_source TASK_BRANCH_PREFIX))"
  printf '  %-24s %-16s %s\n' "TASK_DEFAULT_BASE" "$DEFAULT_BASE" \
    "(from $(cfg_source TASK_DEFAULT_BASE))"
  printf '  %-24s %-16s %s\n' "TASK_DEFAULT_ISOLATION" "$DEFAULT_ISOLATION" \
    "(from $(cfg_source TASK_DEFAULT_ISOLATION))"
  printf '  %-24s %-16s %s\n' "REFERENCE_REPOS" "${REFERENCE_REPOS:--}" \
    "(from $(cfg_source REFERENCE_REPOS))"
  info ""
  info "  a new task would branch:   ${C_BOLD}$BRANCH_PREFIX/<task>${C_RESET}"
  info "  and work:                  ${C_BOLD}$DEFAULT_ISOLATION${C_RESET} unless started with --space or --inplace"
  if [ -n "$REFERENCE_REPOS" ]; then
    info "  read-only everywhere:      ${C_BOLD}${REFERENCE_REPOS}${C_RESET}"
  fi
  info ""
  if [ -f "$(cfg_file)" ]; then
    dim "$(cfg_file) exists (gitignored)"
  else
    dim "no .env yet - cp .env.example .env to set your own"
  fi
  case "$(cfg_source TASK_BRANCH_PREFIX) $(cfg_source TASK_DEFAULT_BASE)" in
    *"(as "*) dim "renamed settings still read from their old SPACE_* names - rename them in .env" ;;
  esac
}

# ------------------------------------------------------------------ list --

cmd_list() {
  local only="${1:-}" task repo wt branch dirty found=0
  for task in $(task_names); do
    [ -n "$only" ] && [ "$task" != "$only" ] && continue
    found=1
    step "$task  ${C_DIM}$(task_isolation "$task")${C_RESET}"
    for repo in $(task_repos "$task"); do
      wt="$(task_workdir "$task" "$repo")"
      if [ ! -e "$wt/.git" ]; then
        printf '  %-12s %-32s %s\n' "$repo" "-" "${C_RED}missing${C_RESET}"
        continue
      fi
      branch="$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
      if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then
        dirty="${C_YELLOW}dirty${C_RESET}"
      else
        dirty="${C_DIM}clean${C_RESET}"
      fi
      printf '  %-12s %-32s %s\n' "$repo" "$branch" "$dirty"
    done
  done
  [ "$found" -eq 1 ] || info "no open tasks"
}

# ---------------------------------------------------------------- report --

# Everything needed to write a wrap-up summary, gathered while the working
# directories still exist. Read-only: never mutates anything.
cmd_report() {
  local task="${1:-}"
  [ -n "$task" ] || die "missing <task>"
  task_exists "$task" || die "no task named '$task' - task.sh list shows what is open"

  printf 'task\t%s\n' "$task"
  printf 'isolation\t%s\n' "$(task_isolation "$task")"
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
  printf 'branch\t%s\n' "$(task_branch "$task")"
  printf 'created\t%s\n' "$(task_field "$task" created)"

  local wt repo branch base base_ref base_sha head upstream ahead behind unpushed dirty
  for repo in $(task_repos "$task"); do
    wt="$(task_workdir "$task" "$repo")"
    printf '\nrepo\t%s\n' "$repo"
    printf 'workdir\t%s\n' "$(rel "$wt")"
    if [ ! -e "$wt/.git" ]; then
      printf 'missing\tno checkout at %s\n' "$(rel "$wt")"
      continue
    fi
    branch="$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
    head="$(git -C "$wt" rev-parse --short HEAD 2>/dev/null || echo '?')"

    base="$(task_base "$task" "$repo" 2>/dev/null || true)"
    base_ref="${base%%	*}"; base_sha="${base#*	}"
    [ -n "$base" ] || { base_ref=""; base_sha=""; }
    # Tasks started before metadata existed: fall back to the fork point.
    if [ -z "$base_sha" ]; then
      base_sha="$(git -C "$wt" merge-base HEAD origin/main 2>/dev/null || echo '')"
      [ -n "$base_sha" ] && base_ref="${base_ref:-origin/main (inferred)}"
    fi

    printf 'branch\t%s\n' "$branch"
    printf 'base\t%s\t%s\n' "${base_ref:-unknown}" "$(printf '%.9s' "${base_sha:-unknown}")"
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

# ---------------------------------------------------------------- finish --

finish_space_repo() {
  local task="$1" repo="$2" del_branch="$3" force="$4"
  local dir="$REPOS_DIR/$repo" wt="$SPACES_DIR/$task/$repo" branch rm_args
  [ -e "$wt" ] || return 0
  branch="$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
  rm_args=(worktree remove "$wt")
  [ "$force" -eq 1 ] && rm_args=(worktree remove --force "$wt")
  if ! git -C "$dir" "${rm_args[@]}" >/dev/null 2>&1; then
    fail "$repo  worktree remove failed"
    return 1
  fi
  ok "$repo  worktree removed"
  if [ "$del_branch" -eq 1 ] && [ -n "$branch" ]; then
    if git -C "$dir" branch -D "$branch" >/dev/null 2>&1; then
      dim "$repo  deleted branch $branch (local only)"
    else
      warn "$repo  could not delete branch $branch"
    fi
  fi
}

# In place: put the checkout back on the branch it was on before the task.
# A checkout someone already moved off the task branch is left where it is.
finish_inplace_repo() {
  local task="$1" repo="$2" del_branch="$3" force="$4"
  local dir="$REPOS_DIR/$repo" branch cur home sw=() left
  branch="$(task_branch "$task")"
  home="$(awk -F'\t' -v r="$repo" '$1=="home" && $2==r {print $3; exit}' "$(task_meta "$task")")"
  if [ -z "$home" ]; then
    home="$(git -C "$dir" symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null)"
    home="${home#origin/}"
    [ -n "$home" ] || home=main
  fi
  cur="$(checkout_head "$dir")"

  if [ "$cur" != "$branch" ]; then
    warn "$repo  is on $cur, not $branch - left as it is"
  else
    case "$home" in
      *[!0-9a-f]*) sw=("$home") ;;
      *)           sw=(--detach "$home") ;;
    esac
    [ "$force" -eq 1 ] && sw=(--discard-changes "${sw[@]}")
    if ! git -C "$dir" switch -q "${sw[@]}" 2>/dev/null; then
      fail "$repo  could not switch repos/$repo back to $home"
      git -C "$dir" switch "${sw[@]}" 2>&1 | sed 's/^/      /' >&2 || true
      return 1
    fi
    ok "$repo  repos/$repo back on $home"
    left="$(git -C "$dir" status --porcelain 2>/dev/null | grep -c '^??' || true)"
    [ "${left:-0}" -gt 0 ] && warn "$repo  $left untracked file(s) from the task remain in repos/$repo"
  fi

  if [ "$del_branch" -eq 1 ]; then
    if git -C "$dir" branch -D "$branch" >/dev/null 2>&1; then
      dim "$repo  deleted branch $branch (local only)"
    else
      warn "$repo  could not delete branch $branch"
    fi
  fi
  return 0
}

cmd_finish() {
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
  task_exists "$task" || die "no task named '$task' - task.sh list shows what is open"
  local isolation repos repo wt failed=0
  isolation="$(task_isolation "$task")"
  if [ -n "$repos_csv" ]; then repos="$(parse_repos "$repos_csv")"; else repos="$(task_repos "$task")"; fi

  step "finishing task ${C_BOLD}$task${C_RESET}  ${C_DIM}$isolation${C_RESET}"

  # Check every repo before touching any, so a blocked finish leaves the whole
  # task intact instead of half torn down.
  if [ "$force" -eq 0 ]; then
    local blocked=0 unpushed
    for repo in $repos; do
      wt="$(task_workdir "$task" "$repo")"
      [ -e "$wt/.git" ] || continue
      if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then
        fail "$repo  has uncommitted changes"
        blocked=$((blocked + 1))
      fi
      # Deleting the branch discards commits that reached no remote.
      if [ "$del_branch" -eq 1 ]; then
        unpushed="$(git -C "$wt" rev-list --count HEAD --not --remotes 2>/dev/null || echo 0)"
        if [ "$unpushed" -gt 0 ]; then
          fail "$repo  $unpushed commit(s) not pushed to any remote"
          blocked=$((blocked + 1))
        fi
      fi
    done
    if [ "$blocked" -gt 0 ]; then
      info ""
      info "nothing changed. Push or stash that work, or re-run with --force to discard it."
      return 1
    fi
  fi

  for repo in $repos; do
    if [ "$isolation" = space ]; then
      finish_space_repo "$task" "$repo" "$del_branch" "$force" || { failed=$((failed + 1)); continue; }
    else
      finish_inplace_repo "$task" "$repo" "$del_branch" "$force" || { failed=$((failed + 1)); continue; }
    fi
    # Its code-review-graph data describes a working directory that is gone.
    if [ -x "$SCRIPT_DIR/graph.sh" ] && [ -n "$("$SCRIPT_DIR/graph.sh" drop "$task" "$repo" 2>/dev/null)" ]; then
      dim "$repo  dropped its code-review-graph data"
    fi
  done
  [ "$failed" -eq 0 ] || return 1

  # Drop the metadata only once every repo in the task is finished.
  local left=0
  for repo in $(task_repos "$task"); do
    case " $(printf '%s ' $repos)" in *" $repo "*) ;; *) left=$((left + 1)) ;; esac
  done
  if [ "$left" -eq 0 ]; then
    rm -f "$TL_STATE/$task" "$SPACES_DIR/$task/.space"
    rmdir "$SPACES_DIR/$task" 2>/dev/null && dim "removed spaces/$task" || true
    dim "task $task closed"
  fi
}

# ----------------------------------------------------------------- slash --

# Entry point for the /task slash command, which expands this eagerly - so it
# must not finish anything on its own. `start` and `list` run for real;
# `finish` answers with the read-only report instead, and the teardown happens
# only after the wrap-up log has been written.
cmd_slash() {
  local sub="${1:-list}"
  [ $# -gt 0 ] && shift
  case "$sub" in
    start|add|new)
      printf 'mode\tstart\n\n'
      cmd_start "$@"
      ;;
    finish|remove|rm)
      local task="" force=0 arg
      for arg in "$@"; do
        case "$arg" in
          --force|-f) force=1 ;;
          -*) ;;
          *) [ -n "$task" ] || task="$arg" ;;
        esac
      done
      printf 'mode\tfinish\nforce\t%s\n\n' "$force"
      cmd_report "$task"
      ;;
    list|ls)
      printf 'mode\tlist\n\n'
      cmd_list "$@"
      ;;
    where)
      printf 'mode\twhere\n\n'
      cmd_where "$@"
      ;;
    repos)
      printf 'mode\trepos\n\n'
      cmd_repos
      ;;
    config)
      printf 'mode\tconfig\n\n'
      cmd_config
      ;;
    -h|--help)
      usage
      ;;
    *)
      printf 'mode\terror\n\n'
      die "unknown command '$sub' - use start, finish, list, where, repos, or config"
      ;;
  esac
}

# ------------------------------------------------------------------ main --

case "${1:-}" in
  ""|-h|--help) usage ;;
  start|add|new)    shift; cmd_start "$@" ;;
  where)            shift; cmd_where "$@" ;;
  root)             printf '%s\n' "$ROOT" ;;
  list|ls)          shift; cmd_list "$@" ;;
  repos)            shift; cmd_repos ;;
  config)           shift; cmd_config ;;
  report)           shift; cmd_report "$@" ;;
  finish|remove|rm) shift; cmd_finish "$@" ;;
  slash)            shift; cmd_slash "$@" ;;
  *) usage; die "unknown command '$1' - use start, where, list, report, finish, repos, or config" ;;
esac
