#!/usr/bin/env bash
#
# guard-test.sh - the hand-test battery for guard.sh.
#
# The guard is the workspace's only enforcement, and it is one long chain of
# regexes over raw command text. Every relaxation in it - a write anywhere in a
# checkout, deleting any branch that is not a source branch, an ASCII arrow in
# prose - is one a plausible tightening would undo without anyone noticing. So each is pinned here, next
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

# The reference-repo and source-branch cases need known settings, and the
# machine .env must not decide the outcome. The environment wins over .env, so
# pin them here: `mobile` and `partner` are reference-only for the duration of
# this run, `backend`, `sport` and `player` are not, and main is the default
# base - a source branch of every repo.
export REFERENCE_REPOS=mobile,partner
export TASK_DEFAULT_BASE=origin/main

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
# Checkouts are writable like a space's worktrees. repos/ itself, a checkout
# root and its .git hold the branches, so those are not.
wr_case allow repos/backend/x.ts
wr_case allow repos/backend/docs/a.md
wr_case allow "$ROOT/repos/sport/main.go"
wr_case block repos/
wr_case block repos/backend/.git/config
wr_case allow repos/README.md
wr_case allow "$ROOT/repos/README.md"
wr_case allow repos/README.md.bak
wr_case allow spaces/some-task/backend/src/x.ts
wr_case allow .claude/scripts/task.sh
wr_case block repos/mobile/src/App.tsx

# --- redirects -------------------------------------------------------------
sh_case allow 'cd repos/backend && ls 2>/dev/null'
sh_case allow 'cd repos/backend && git log --oneline -5 2>/dev/null'
sh_case allow 'cd repos/backend && cat package.json 2>&1'
sh_case allow 'cd repos/backend && grep -rn foo src 2>/dev/null | head -5'
sh_case allow 'cd repos/backend && npm ls > /tmp/out.txt'
sh_case allow "cd repos/backend && npm ls > $ROOT/spaces/x.txt"
sh_case allow 'cd repos/backend && npm ls > $SP/out.txt'
sh_case allow 'cd repos/backend && npm ls > "$SCRATCH/out.txt" 2>&1'
sh_case allow 'cd repos/backend && echo hi > file.txt'
sh_case allow 'cd repos/backend && echo hi >> src/app.ts'
sh_case allow "cd repos/backend && echo hi > $ROOT/repos/backend/f.txt"
sh_case block 'cd repos/backend && echo x > .git/HEAD'
sh_case block 'echo x > repos/backend/.git/HEAD'

# --- git in a checkout: anything but deleting a source branch --------------
# TASK_DEFAULT_BASE is pinned to origin/main above, so main is a source branch
# of every repo here.
sh_case allow 'git -C repos/backend branch --list'
sh_case allow 'git -C repos/backend branch -a'
sh_case allow 'git -C repos/backend branch --merged main'
sh_case allow 'git -C repos/backend branch --show-current'
sh_case allow 'git -C repos/backend branch'
sh_case allow 'git -C repos/backend tag -l'
sh_case allow 'git -C repos/backend worktree list'
sh_case allow "git -C $ROOT/repos/sport branch --format='%(refname:short)'"
sh_case allow 'git -C repos/backend branch -d feature'
sh_case allow 'git -C repos/backend branch -D feature'
sh_case allow 'git -C repos/backend branch newthing'
sh_case allow 'git -C repos/backend branch -m old new'
sh_case allow 'git -C repos/backend tag v1.0.0'
sh_case allow 'git -C repos/backend worktree add ../x'
sh_case allow 'git -C repos/backend stash pop'
sh_case allow 'git -C repos/backend checkout main'
sh_case allow 'git -C repos/backend commit -m x'
sh_case allow 'git -C repos/backend push'
sh_case allow 'git -C repos/backend push origin main'
sh_case allow 'git -C repos/backend reset --hard'
sh_case allow "sudo git -C $ROOT/repos/player pull"
sh_case allow 'git -C repos/backend push origin --delete feature'
sh_case allow 'git -C repos/backend fetch --prune'
sh_case allow 'cd repos/backend && git checkout -b x'
sh_case block 'git -C repos/backend branch -d main'
sh_case block 'git -C repos/backend branch -D feature main'
sh_case block 'git -C repos/backend branch --delete main'
sh_case block 'git -C repos/backend branch -dr origin/main'
sh_case block 'git -C repos/backend branch -m main trunk'
sh_case block 'git -C repos/backend push origin --delete main'
sh_case block 'git -C repos/backend push -d origin main'
sh_case block 'git -C repos/backend push origin :main'
sh_case block 'git -C repos/backend push origin +:refs/heads/main'
sh_case block 'git -C repos/backend push --mirror origin'
sh_case block 'git -C repos/backend push --prune origin'
sh_case block 'git -C repos/backend update-ref -d refs/heads/main'
sh_case block 'git -C repos/backend branch --list; git -C repos/backend branch -d main'
sh_case block 'cd repos/backend && git branch -D main'

# --- an ASCII arrow is not a redirect --------------------------------------
sh_case allow 'echo "spaces/x/backend -> repos/backend"'
sh_case allow 'printf "%s\n" "worktree: spaces/t/sport -> repos/sport"'
sh_case allow 'echo "map => repos/player"'
sh_case allow 'cat <<EOF
spaces/t/backend -> repos/backend
EOF'
sh_case allow 'echo hi > repos/backend/f.txt'
sh_case block 'echo hi > repos/mobile/f.txt'

# --- the roster, and loose files beside the checkouts ----------------------
sh_case allow 'echo "# repos" > repos/README.md'
sh_case allow 'tee repos/README.md < /tmp/x'
sh_case allow 'tee repos/backend/README.md < /tmp/x'
sh_case allow 'rm repos/README.md.bak'

# --- file commands in checkouts --------------------------------------------
sh_case allow 'rm -rf repos/backend/src'
sh_case allow 'mv repos/backend/a repos/backend/b'
sh_case allow 'touch repos/sport/x.go'
sh_case allow 'mkdir repos/newthing'
sh_case allow 'sed -i "" s/a/b/ repos/backend/src/x.ts'
sh_case allow 'perl -i -pe s/a/b/ repos/sport/main.go'
sh_case allow 'cd repos/backend && rm -rf src'
sh_case block 'rm -rf repos/backend/.git'
sh_case block 'cd repos/backend && rm -rf .git'
sh_case block 'rm -rf repos'

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
sh_case block 'git -C spaces/some-task/backend push origin --delete main'
sh_case block 'cd spaces/some-task/backend && git branch -D main'

# --- reference repos are read-only in repos/ and in a space ----------------
# See REFERENCE_REPOS in .env.example.
wr_case block repos/mobile/src/x.ts
wr_case block spaces/some-task/mobile/src/App.tsx
wr_case block spaces/some-task/partner/main.go
wr_case block "$ROOT/spaces/some-task/mobile/src/App.tsx"
wr_case block spaces/some-task/mobile
wr_case allow spaces/some-task/mobile-app/src/App.tsx
wr_case allow spaces/mobile/backend/src/x.ts
wr_case allow spaces/some-task/backend/src/mobile/x.ts
sh_case block 'git -C repos/mobile commit -m x'
sh_case block 'git -C repos/partner checkout -b x'
sh_case block 'cd repos/partner && rm -rf src'
sh_case block 'echo hi > spaces/some-task/mobile/f.txt'
sh_case block 'rm -rf spaces/some-task/partner/src'
sh_case block 'sed -i "" s/a/b/ spaces/some-task/mobile/src/App.tsx'
sh_case block 'git -C spaces/some-task/mobile commit -m x'
sh_case block 'git -C spaces/some-task/mobile add -A'
sh_case block 'cd spaces/some-task/mobile && git commit -m x'
sh_case block 'cd spaces/some-task/mobile && rm -rf src'
sh_case block 'cd spaces/some-task/mobile && echo hi > f.txt'
sh_case allow 'git -C repos/mobile log --oneline -5'
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
sh_case allow 'rm -rf ./repos/backend/x'
sh_case allow 'cp /tmp/a.txt repos/backend/a.txt'
sh_case allow "touch $ROOT/repos/backend/f"

# --- plain commands run where the session is -----------------------------
CWD="$ROOT/repos/backend" sh_case allow 'git commit -m x'
CWD="$ROOT/repos/backend" sh_case allow 'git switch -c mine'
CWD="$ROOT/repos/backend" sh_case allow 'echo hi > f.txt'
CWD="$ROOT/repos/backend" sh_case allow 'rm -rf src'
CWD="$ROOT/repos/backend" sh_case allow 'git status'
CWD="$ROOT/repos/backend" sh_case allow 'git log --oneline -3 2>/dev/null'
CWD="$ROOT/repos/backend" sh_case allow 'grep -rn foo src > /tmp/hits.txt'
CWD="$ROOT/repos/backend" sh_case block 'git branch -D main'
CWD="$ROOT/repos/backend" sh_case block 'rm -rf .git'
CWD="$ROOT/repos/partner" sh_case block 'git commit -m x'
CWD="$ROOT/spaces/t/backend" sh_case allow 'git commit -m x'
CWD="$ROOT/spaces/t/backend" sh_case block 'git push origin :main'

# --- source branches, read from each checkout and the task metadata --------
# Real checkouts and task records, in a fixture workspace with its own copy of
# the guard. repos/app's source branches: main (TASK_DEFAULT_BASE), trunk (its
# origin/HEAD), release-2 (t1's base) and develop (where t1 returns it).
FIX="$(mktemp -d "${TMPDIR:-/tmp}/guard-test.XXXXXX")"
trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/.claude/scripts" "$FIX/.claude/state/tasks" "$FIX/gitdirs/wt" "$FIX/spaces/t3/app"
cp "$SCRIPT_DIR/guard.sh" "$SCRIPT_DIR/config.sh" "$FIX/.claude/scripts/"
FIX="$(cd "$FIX" && pwd -P)"
head_on() { mkdir -p "$FIX/repos/$1/.git"; printf 'ref: refs/heads/%s\n' "$2" >"$FIX/repos/$1/.git/HEAD"; }
head_on app    me/t1
head_on mobile me/t1        # reference-only
mkdir -p "$FIX/repos/app/.git/refs/remotes/origin" "$FIX/repos/app/.git/refs/remotes/upstream"
printf 'ref: refs/remotes/origin/trunk\n' >"$FIX/repos/app/.git/refs/remotes/origin/HEAD"
mkdir -p "$FIX/repos/wt"; printf 'gitdir: ../../gitdirs/wt\n' >"$FIX/repos/wt/.git"
printf 'ref: refs/heads/main\n' >"$FIX/gitdirs/wt/HEAD"
printf 'gitdir: %s/repos/app/.git/worktrees/app\n' "$FIX" >"$FIX/spaces/t3/app/.git"
printf 'task\tt1\nisolation\tinplace\nbranch\tme/t1\nbase\tapp\torigin/release-2\tabc\nhome\tapp\tdevelop\n' \
  >"$FIX/.claude/state/tasks/t1"
printf 'task\tt3\nisolation\tspace\nbranch\tme/t3\nbase\tapp\torigin/main\tabc\n' >"$FIX/.claude/state/tasks/t3"

G="$FIX/.claude/scripts/guard.sh"
CWD="$FIX"
wr_case allow repos/app/src/x.ts
wr_case allow "$FIX/repos/app/README.md"
wr_case allow repos/wt/src/x.ts
wr_case allow repos/newthing/x.ts
wr_case block repos/app
wr_case block repos/app/.git/config
wr_case block repos/wt/.git
wr_case block repos/mobile/src/x.ts
sh_case allow 'echo hi > repos/app/f.txt'
sh_case allow 'rm -rf repos/app/build'
sh_case allow 'rm -rf repos/app/*'
sh_case allow 'mkdir repos/newthing'
sh_case block 'rm -rf repos/app'
sh_case block 'rm -rf repos/app/'
sh_case block 'rm -rf repos/app/.git'
sh_case block 'rm repos/app/.git/refs/heads/main'
sh_case block 'rm -rf repos/app/.*'
sh_case block 'rm -rf repos/*'
sh_case block 'mv repos/app repos/app-old'
sh_case block 'echo x > repos/app/.git/HEAD'
sh_case allow 'git -C repos/app add -A'
sh_case allow 'git -C repos/app commit -m x'
sh_case allow 'git -C repos/app checkout main'
sh_case allow 'git -C repos/app switch -c tmp'
sh_case allow 'git -C repos/app reset --hard HEAD~1'
sh_case allow 'git -C repos/app rebase origin/main'
sh_case allow 'git -C repos/app pull'
sh_case allow 'git -C repos/app push origin main'
sh_case allow 'git -C repos/app push -u origin me/t1'
sh_case allow 'git -C repos/app push origin me/t1:main'
sh_case allow 'git -C repos/app branch -D old'
sh_case allow 'git -C repos/app branch -d me/t1'
sh_case allow 'git -C repos/app push origin --delete me/t1'
sh_case allow 'git -C repos/app push origin :old'
sh_case allow 'git -C repos/app branch -m old new'
sh_case allow 'git -C repos/app branch -m renamed'
sh_case allow 'git -C repos/app update-ref -d refs/heads/old'
sh_case allow 'git -C repos/app branch -dr upstream/old'
sh_case block 'git -C repos/app branch -d main'
sh_case block 'git -C repos/app branch -D trunk'
sh_case block 'git -C repos/app branch --delete release-2'
sh_case block 'git -C repos/app branch -D develop'
sh_case block 'git -C repos/app branch -D old main'
sh_case block 'git -C repos/app branch -dr origin/trunk'
sh_case block 'git -C repos/app branch -dr upstream/release-2'
sh_case block 'git -C repos/app branch -m main trunk2'
sh_case block 'git -C repos/app branch -M develop dev'
sh_case block 'git -C repos/app push origin --delete main'
sh_case block 'git -C repos/app push -d origin release-2'
sh_case block 'git -C repos/app push origin :main'
sh_case block 'git -C repos/app push origin +:refs/heads/trunk'
sh_case block 'git -C repos/app push origin me/t1 :develop'
sh_case block 'git -C repos/app push upstream --delete develop'
sh_case block 'git -C repos/app push --mirror origin'
sh_case block 'git -C repos/app push --prune origin'
sh_case block 'git -C repos/app update-ref -d refs/heads/main'
sh_case block 'git -C repos/app update-ref -d refs/remotes/origin/trunk'
sh_case block 'cd repos/app && git add -A && git branch -D main'
sh_case block "git -C $FIX/repos/app branch -D main"
sh_case block 'git -C repos/wt branch -m renamed'       # HEAD is main
sh_case block 'git -C repos/mobile commit -m x'
CWD="$FIX/repos/app" sh_case allow 'git commit -m x'
CWD="$FIX/repos/app" sh_case allow 'echo hi > f.txt'
CWD="$FIX/repos/app" sh_case allow 'rm -rf build'
CWD="$FIX/repos/app" sh_case allow 'cp .env.example .env'
CWD="$FIX/repos/app" sh_case block 'git branch -D main'
CWD="$FIX/repos/app" sh_case block 'rm -rf .git'
CWD="$FIX/repos/app" sh_case block 'rm -rf .'
CWD="$FIX/repos/app" sh_case block 'echo x > .git/HEAD'
CWD="$FIX/repos/app/src" sh_case block 'rm -rf ../.git'
# A space: writable, and its source branches are its repo's.
sh_case allow 'git -C spaces/t3/app commit -m x'
sh_case allow 'git -C spaces/t3/app push origin --delete me/t3'
sh_case allow 'rm -rf spaces/t3/app/build'
sh_case block 'git -C spaces/t3/app push origin --delete release-2'
sh_case block 'cd spaces/t3/app && git branch -D main'
CWD="$FIX/spaces/t3/app" sh_case block 'git push origin :trunk'
# Unreadable metadata: the source branches are unknown, so every branch is.
chmod 000 "$FIX/.claude/state/tasks/t1"
sh_case block 'git -C repos/app branch -D old'
sh_case block 'git -C repos/app push origin --delete me/t1'
sh_case allow 'git -C repos/app commit -m x'
wr_case allow repos/app/src/x.ts
chmod 644 "$FIX/.claude/state/tasks/t1"
sh_case allow 'git -C repos/app branch -D old'
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
