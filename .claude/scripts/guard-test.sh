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

QUIET=0
[ "${1:-}" = "-q" ] && QUIET=1

pass=0
fail=0

# payload <tool> <key> <value> - a hook payload as JSON, cwd pinned to ROOT.
payload() {
  python3 -c 'import json,sys; print(json.dumps({"tool_name":sys.argv[1],"cwd":sys.argv[2],"tool_input":{sys.argv[3]:sys.argv[4]}}))' \
    "$1" "$ROOT" "$2" "$3"
}

check() { # check <expect> <tool> <key> <value>
  local expect="$1" json got rc
  json="$(payload "$2" "$3" "$4")"
  printf '%s' "$json" | "$GUARD" >/dev/null 2>&1
  rc=$?
  got=allow
  [ "$rc" -eq 2 ] && got=block
  if [ "$got" = "$expect" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    [ "$QUIET" -eq 1 ] || printf 'FAIL\twant=%s\tgot=%s\t%s\n' "$expect" "$got" "$4"
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
wr_case allow .claude/scripts/space.sh

# --- a redirect after `cd repos/` only counts if it lands in repos/ ---------
sh_case allow 'cd repos/backend && ls 2>/dev/null'
sh_case allow 'cd repos/backend && git log --oneline -5 2>/dev/null'
sh_case allow 'cd repos/backend && cat package.json 2>&1'
sh_case allow 'cd repos/backend && grep -rn foo src 2>/dev/null | head -5'
sh_case allow 'cd repos/backend && npm ls > /tmp/out.txt'
sh_case allow "cd repos/backend && npm ls > $ROOT/spaces/x.txt"
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
