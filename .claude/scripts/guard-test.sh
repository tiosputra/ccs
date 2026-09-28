#!/usr/bin/env bash
#
# guard-test.sh - the hand-test battery for guard.sh.
#
# The guard is the workspace's only enforcement, and it is one long chain of
# regexes over raw command text. Every relaxation in it - a redirect to
# /dev/null, `git branch --list`, an ASCII arrow in prose - is one a plausible
# tightening would undo without anyone noticing. So each is pinned here, next
# to the writes that must still be refused.
#
# Usage:
#   guard-test.sh            run every case, print failures, exit 1 if any
#   guard-test.sh -q         print only the pass/fail tally
#
# Cases are `expect` = block (guard exits 2) or allow (guard exits 0). Add one
# whenever you touch guard.sh, in whichever direction the change moved.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GUARD="$SCRIPT_DIR/guard.sh"

# The reference-repo cases need a known list, and the machine .env must not
# decide the outcome. The environment wins over .env, so pin it here: `mobile`
# and `partner` are reference-only for the duration of this run, `backend`,
# `sport` and `player` are not.
export REFERENCE_REPOS=mobile,partner

QUIET=0
[ "${1:-}" = "-q" ] && QUIET=1

pass=0
fail=0

# payload <tool> <key> <value> - a hook payload as JSON, cwd pinned to CWD
# (ROOT unless a case says otherwise).
payload() {
  python3 -c 'import json,sys; print(json.dumps({"tool_name":sys.argv[1],"cwd":sys.argv[2],"tool_input":{sys.argv[3]:sys.argv[4]}}))' \
    "$1" "${CWD:-$ROOT}" "$2" "$3"
}

check() { # check <expect> <tool> <key> <value>
  local expect="$1" json got rc
  json="$(payload "$2" "$3" "$4")"
  printf '%s' "$json" | "${G:-$GUARD}" >/dev/null 2>&1
  rc=$?
  got=allow
  [ "$rc" -eq 2 ] && got=block
  if [ "$got" = "$expect" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    [ "$QUIET" -eq 1 ] || printf 'FAIL\twant=%s\tgot=%s\t%s%s\n' "$expect" "$got" "$4" "${CWD:+  (cwd ${CWD#"${FIX:-$ROOT}"/})}"
  fi
}

sh_case() { check "$1" Bash command "$2"; }
wr_case() { check "$1" Write file_path "$2"; }

# --- file-writing tools ----------------------------------------------------
wr_case block repos/backend/x.ts
wr_case block repos/backend/docs/a.md
wr_case block "$ROOT/repos/sport/main.go"
wr_case block repos/
wr_case allow repos/README.md
wr_case allow "$ROOT/repos/README.md"
wr_case block repos/README.md.bak
wr_case block repos/README.mdx
wr_case allow spaces/some-task/backend/src/x.ts
wr_case allow .claude/scripts/task.sh

# --- a redirect after `cd repos/` only counts if it lands in repos/ ---------
sh_case allow 'cd repos/backend && ls 2>/dev/null'
sh_case allow 'cd repos/backend && git log --oneline -5 2>/dev/null'
sh_case allow 'cd repos/backend && cat package.json 2>&1'
sh_case allow 'cd repos/backend && grep -rn foo src 2>/dev/null | head -5'
sh_case allow 'cd repos/backend && npm ls > /tmp/out.txt'
sh_case allow "cd repos/backend && npm ls > $ROOT/spaces/x.txt"
sh_case allow 'cd repos/backend && npm ls > $SP/out.txt'
sh_case allow 'cd repos/backend && npm ls > "$SCRATCH/out.txt" 2>&1'
sh_case block 'cd repos/backend && echo hi > file.txt'
sh_case block 'cd repos/backend && echo hi >> src/app.ts'
sh_case block "cd repos/backend && echo hi > $ROOT/repos/backend/f.txt"

# --- read-only forms of the dual git verbs ---------------------------------
sh_case allow 'git -C repos/backend branch --list'
sh_case allow 'git -C repos/backend branch -a'
sh_case allow 'git -C repos/backend branch --merged main'
sh_case allow 'git -C repos/backend branch --show-current'
sh_case allow 'git -C repos/backend branch'
sh_case allow 'git -C repos/backend tag -l'
sh_case allow 'git -C repos/backend tag --list "v*"'
sh_case allow 'git -C repos/backend worktree list'
sh_case allow 'git -C repos/backend stash list'
sh_case allow "git -C $ROOT/repos/sport branch --format='%(refname:short)'"
sh_case allow 'cd repos/backend && git branch --list'
sh_case block 'git -C repos/backend branch -d feature'
sh_case block 'git -C repos/backend branch -D feature'
sh_case block 'git -C repos/backend branch newthing'
sh_case block 'git -C repos/backend branch -m old new'
sh_case block 'git -C repos/backend tag v1.0.0'
sh_case block 'git -C repos/backend tag -d v1.0.0'
sh_case block 'git -C repos/backend worktree add ../x'
sh_case block 'git -C repos/backend worktree prune'
sh_case block 'git -C repos/backend stash'
sh_case block 'git -C repos/backend stash pop'
sh_case block 'git -C repos/backend branch --list; git -C repos/backend branch -d x'
sh_case block 'cd repos/backend && git branch -d feature'

# --- an ASCII arrow is not a redirect --------------------------------------
sh_case allow 'echo "spaces/x/backend -> repos/backend"'
sh_case allow 'printf "%s\n" "worktree: spaces/t/sport -> repos/sport"'
sh_case allow 'echo "map => repos/player"'
sh_case allow 'cat <<EOF
spaces/t/backend -> repos/backend
EOF'
sh_case block 'echo hi > repos/backend/f.txt'
sh_case block 'echo hi >> repos/sport/f.txt'
sh_case block "echo hi > $ROOT/repos/sport/f.txt"

# --- the roster is writable, the checkouts are not -------------------------
sh_case allow 'echo "# repos" > repos/README.md'
sh_case allow 'tee repos/README.md < /tmp/x'
sh_case block 'tee repos/backend/README.md < /tmp/x'
sh_case block 'rm repos/README.md.bak'

# --- writes into repos/ stay blocked ---------------------------------------
sh_case block 'git -C repos/backend checkout main'
sh_case block 'git -C repos/backend commit -m x'
sh_case block 'git -C repos/backend push'
sh_case block 'git -C repos/backend reset --hard'
sh_case block "sudo git -C $ROOT/repos/player pull"
sh_case block 'rm -rf repos/backend/src'
sh_case block 'mv repos/backend/a repos/backend/b'
sh_case block 'touch repos/sport/x.go'
sh_case block 'mkdir repos/newthing'
sh_case block 'sed -i "" s/a/b/ repos/backend/src/x.ts'
sh_case block 'perl -i -pe s/a/b/ repos/sport/main.go'
sh_case block 'cd repos/backend && rm -rf src'
sh_case block 'cd repos/backend && git checkout -b x'

# --- reads, and git inside a space, stay allowed ---------------------------
sh_case allow 'grep -rn "git add" CLAUDE.md'
sh_case allow 'git -C repos/backend log --oneline -5'
sh_case allow 'git -C repos/backend status'
sh_case allow 'git -C repos/backend for-each-ref --format="%(refname)"'
sh_case allow 'git -C repos/backend remote -v'
sh_case allow 'cat repos/backend/package.json'
sh_case allow 'ls repos/'
sh_case allow 'git -C spaces/some-task/backend commit -m "work"'
sh_case allow 'git -C spaces/some-task/backend push'
sh_case allow 'cd spaces/some-task/backend && git add -A && git commit -m x'
sh_case allow 'echo hi > spaces/some-task/backend/f.txt'
sh_case allow 'npm test -- --maxWorkers=2 2>/dev/null'

# --- reference repos are read-only in a space too --------------------------
# repos/ already seals every checkout; these pin the part that is new - a
# reference repo stays sealed inside spaces/, where every other repo is
# writable. See REFERENCE_REPOS in .env.example.
wr_case block spaces/some-task/mobile/src/App.tsx
wr_case block spaces/some-task/partner/main.go
wr_case block "$ROOT/spaces/some-task/mobile/src/App.tsx"
wr_case block spaces/some-task/mobile
wr_case allow spaces/some-task/mobile-app/src/App.tsx
wr_case allow spaces/mobile/backend/src/x.ts
wr_case allow spaces/some-task/backend/src/mobile/x.ts
sh_case block 'echo hi > spaces/some-task/mobile/f.txt'
sh_case block 'rm -rf spaces/some-task/partner/src'
sh_case block 'sed -i "" s/a/b/ spaces/some-task/mobile/src/App.tsx'
sh_case block 'git -C spaces/some-task/mobile commit -m x'
sh_case block 'git -C spaces/some-task/mobile add -A'
sh_case block 'cd spaces/some-task/mobile && git commit -m x'
sh_case block 'cd spaces/some-task/mobile && rm -rf src'
sh_case block 'cd spaces/some-task/mobile && echo hi > f.txt'
sh_case allow 'git -C spaces/some-task/mobile log --oneline -5'
sh_case allow 'git -C spaces/some-task/mobile status'
sh_case allow 'cat spaces/some-task/mobile/package.json'
sh_case allow 'grep -rn useEffect spaces/some-task/mobile/src'
sh_case allow 'cd spaces/some-task/mobile && ls 2>/dev/null'
sh_case allow 'cd spaces/some-task/mobile && npm ls > /tmp/out.txt'
sh_case allow 'git -C spaces/some-task/mobile-app commit -m x'
sh_case allow 'echo "spaces/t/backend -> spaces/t/mobile"'

# --- file commands judge the paths they name, not words that look like one -
sh_case allow 'mkdir -p "$SP/ws/repos" "$SP/ws/spaces"'
sh_case allow 'mkdir -p /tmp/scratch/repos/api'
sh_case allow 'rm -rf myrepos/x'
sh_case allow "cp $ROOT/spaces/t/api/a.txt /tmp/a.txt"
sh_case block 'rm -rf ./repos/backend/x'
sh_case block 'cp /tmp/a.txt repos/backend/a.txt'
sh_case block "touch $ROOT/repos/backend/f"
sh_case block 'rm -rf repos'

# --- plain commands run where the session is -----------------------------
# A `git commit` with no cd, from a session already inside a sealed checkout,
# is the same write as `cd repos/<repo> && git commit`.
CWD="$ROOT/repos/backend" sh_case block 'git commit -m x'
CWD="$ROOT/repos/backend" sh_case block 'git switch -c mine'
CWD="$ROOT/repos/backend" sh_case block 'echo hi > f.txt'
CWD="$ROOT/repos/backend" sh_case block 'rm -rf src'
CWD="$ROOT/repos/backend" sh_case allow 'git status'
CWD="$ROOT/repos/backend" sh_case allow 'git log --oneline -3 2>/dev/null'
CWD="$ROOT/repos/backend" sh_case allow 'grep -rn foo src > /tmp/hits.txt'
CWD="$ROOT/spaces/t/backend" sh_case allow 'git commit -m x'

# --- in-place tasks: a checkout a task holds -------------------------------
# Ownership reads files - each checkout's HEAD and the task metadata - so these
# run against a fixture workspace with its own copy of the guard.
FIX="$(mktemp -d "${TMPDIR:-/tmp}/guard-test.XXXXXX")"
trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/.claude/scripts" "$FIX/.claude/state/tasks" "$FIX/gitdirs/wt"
cp "$SCRIPT_DIR/guard.sh" "$SCRIPT_DIR/config.sh" "$FIX/.claude/scripts/"
FIX="$(cd "$FIX" && pwd -P)"
head_on() { mkdir -p "$FIX/repos/$1/.git"; printf 'ref: refs/heads/%s\n' "$2" >"$FIX/repos/$1/.git/HEAD"; }
head_on owned    me/t1       # t1 holds it: HEAD on me/t1 and listed in t1
head_on other    main        # no task
head_on handmade me/t2       # a task-looking branch nobody recorded
head_on spaced   me/t3       # its task is a space, not in place
head_on mobile   me/t1       # reference-only, whatever t1 says
mkdir -p "$FIX/repos/wt"; printf 'gitdir: ../../gitdirs/wt\n' >"$FIX/repos/wt/.git"
printf 'ref: refs/heads/me/t1\n' >"$FIX/gitdirs/wt/HEAD"
printf 'task\tt1\nisolation\tinplace\nbranch\tme/t1\nbase\towned\torigin/main\tabc\nbase\twt\torigin/main\tabc\nbase\tmobile\torigin/main\tabc\n' \
  >"$FIX/.claude/state/tasks/t1"
printf 'task\tt3\nisolation\tspace\nbranch\tme/t3\nbase\tspaced\torigin/main\tabc\n' >"$FIX/.claude/state/tasks/t3"

G="$FIX/.claude/scripts/guard.sh"
CWD="$FIX"
wr_case allow repos/owned/src/x.ts
wr_case allow "$FIX/repos/owned/README.md"
wr_case allow repos/wt/src/x.ts
wr_case block repos/owned
wr_case block repos/owned/.git/config
wr_case block repos/other/src/x.ts
wr_case block repos/handmade/src/x.ts
wr_case block repos/spaced/src/x.ts
wr_case block repos/mobile/src/x.ts
sh_case allow 'echo hi > repos/owned/f.txt'
sh_case allow 'rm -rf repos/owned/build'
sh_case allow 'sed -i "" s/a/b/ repos/owned/src/x.ts'
sh_case block 'rm -rf repos/owned'
sh_case block 'rm -rf repos/owned/.git'
sh_case block 'echo hi > repos/other/f.txt'
sh_case block 'rm -rf repos/other/build'
sh_case allow 'git -C repos/owned add -A'
sh_case allow 'git -C repos/owned commit -m "fix: x"'
sh_case allow 'git -C repos/owned push'
sh_case allow 'git -C repos/owned push -u origin me/t1'
sh_case allow 'git -C repos/owned push origin HEAD'
sh_case allow 'git -C repos/owned push --force-with-lease origin me/t1'
sh_case allow 'git -C repos/owned push origin refs/heads/me/t1'
sh_case allow 'git -C repos/owned log --oneline -5'
sh_case allow 'git -C repos/owned fetch origin'
sh_case allow 'cd repos/owned && git add -A && git commit -m x && git push -u origin me/t1'
sh_case block 'git -C repos/owned push origin main'
sh_case block 'git -C repos/owned push origin me/t1:main'
sh_case block 'git -C repos/owned push origin HEAD:main'
sh_case block 'git -C repos/owned push --all'
sh_case block 'git -C repos/owned push origin --delete me/t1'
sh_case block 'git -C repos/owned push origin :me/t1'
sh_case block 'git -C repos/owned checkout main'
sh_case block 'git -C repos/owned switch main'
sh_case block 'git -C repos/owned reset --hard HEAD~1'
sh_case block 'git -C repos/owned rebase origin/main'
sh_case block 'git -C repos/owned pull'
sh_case block 'git -C repos/owned merge origin/main'
sh_case block 'git -C repos/owned branch -D old'
sh_case block 'cd repos/owned && git add -A && git push origin main'
sh_case block 'git -C repos/other commit -m x'
sh_case block 'git -C repos/handmade commit -m x'
sh_case block 'git -C repos/mobile commit -m x'
CWD="$FIX/repos/owned" sh_case allow 'git commit -m x'
CWD="$FIX/repos/owned" sh_case allow 'echo hi > f.txt'
CWD="$FIX/repos/owned" sh_case allow 'rm -rf build'
CWD="$FIX/repos/owned" sh_case block 'git switch main'
CWD="$FIX/repos/owned" sh_case block 'git push origin main'
CWD="$FIX/repos/other" sh_case block 'git commit -m x'
CWD="$FIX/repos/other" sh_case allow 'git status'
# The task moved off: HEAD no longer on the task branch, so the checkout seals.
head_on owned main
sh_case block 'git -C repos/owned commit -m x'
wr_case block repos/owned/src/x.ts
# Unreadable metadata fails closed.
head_on owned me/t1
chmod 000 "$FIX/.claude/state/tasks/t1"
wr_case block repos/owned/src/x.ts
chmod 644 "$FIX/.claude/state/tasks/t1"
unset G CWD

# --- a malformed payload must never brick the session ----------------------
for bad in 'not json at all' '{}' '{"tool_name":"Bash"}' '{"tool_name":"Write","tool_input":{}}'; do
  printf '%s' "$bad" | "$GUARD" >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    [ "$QUIET" -eq 1 ] || printf 'FAIL\twant=allow\tgot=block\t%s\n' "$bad"
  fi
done

printf 'pass=%d\tfail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
