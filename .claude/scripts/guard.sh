#!/usr/bin/env bash
#
# guard.sh - PreToolUse hook. Enforces the one workspace rule that CLAUDE.md
# can only ask for:
#
#   repos/ is read-only. Never write there, and never run a git command that
#   moves those checkouts. All work happens in spaces/<task>/<repo>/, where
#   git add / commit / push are allowed and expected - /pr uses them.
#
# Reads the hook payload as JSON on stdin. Exit 0 allows the call; exit 2
# blocks it and shows stderr to the agent so it can correct course.
#
# Anything unexpected (bad JSON, missing fields, no python3) exits 0. A guard
# that bricks the session on a malformed payload is worse than no guard.
#
# Test it by hand:
#   echo '{"tool_name":"Write","tool_input":{"file_path":"repos/backend/x.ts"}}' \
#     | .claude/scripts/guard.sh; echo "exit=$?"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

command -v python3 >/dev/null 2>&1 || exit 0

ROOT="$ROOT" exec python3 -c '
import json, os, re, sys

def allow():  sys.exit(0)
def block(msg):
    sys.stderr.write(msg + "\n")
    sys.exit(2)

try:
    payload = json.load(sys.stdin)
except Exception:
    allow()

ROOT  = os.path.realpath(os.environ["ROOT"])
REPOS = os.path.join(ROOT, "repos")
tool  = payload.get("tool_name", "")
inp   = payload.get("tool_input") or {}
cwd   = payload.get("cwd") or os.getcwd()

def under_repos(path):
    """True if path lands inside <root>/repos, however it was written."""
    if not path:
        return False
    p = path if os.path.isabs(path) else os.path.join(cwd, path)
    p = os.path.realpath(p)
    return p == REPOS or p.startswith(REPOS + os.sep)

WRITE_HINT = (
    "repos/ is read-only in this workspace (see CLAUDE.md).\n"
    "Work in the task space instead: spaces/<task>/<repo>/... - git add, commit\n"
    "and push are all allowed there.\n"
    "No space yet? Ask the user for the repos and the source branch, then\n"
    "run: .claude/scripts/space.sh add <task> <repos> --from <source-branch>"
)

# ---- file-writing tools -------------------------------------------------
if tool in ("Write", "Edit", "NotebookEdit", "MultiEdit"):
    for key in ("file_path", "notebook_path", "path"):
        if under_repos(inp.get(key)):
            block("BLOCKED: refusing to write " + str(inp[key]) + "\n\n" + WRITE_HINT)
    for e in inp.get("edits") or []:
        if isinstance(e, dict) and under_repos(e.get("file_path")):
            block("BLOCKED: refusing to write " + str(e["file_path"]) + "\n\n" + WRITE_HINT)
    allow()

if tool != "Bash":
    allow()

cmd = inp.get("command") or ""

# A command position is the start of the line or just after ; && || | & (
# Matching only there keeps quoted prose - grep "git add" CLAUDE.md - from
# tripping the guard.
CMDPOS = r"(?:^|[\n;&|(]|&&|\|\|)\s*"

# git add / commit / push are allowed - inside a space. Only repos/ is sealed.
# ---- repos/ protection, shell edition -----------------------------------
# Any repos/ path written as a bare relative path, or as an absolute path.
REPOS_PATH = r"(?:" + re.escape(REPOS) + r"|(?<![\w./-])repos)/\S+"

# git run against a repos/ checkout with a subcommand that mutates it.
MUTATING = ("add|commit|checkout|switch|merge|rebase|reset|revert|restore|"
            "stash|cherry-pick|apply|am|push|pull|fetch|clean|rm|mv|branch|"
            "tag|worktree|gc|prune")
if re.search(CMDPOS + r"(?:sudo\s+)?git\s+-C\s+(?:\"|\x27)?" + REPOS_PATH
             + r"(?:\"|\x27)?\s+(?:-\S+\s+)*(?:" + MUTATING + r")\b", cmd):
    block("BLOCKED: that git command would mutate a repos/ checkout.\n\n" + WRITE_HINT)

# Redirections into repos/.
if re.search(r">>?\s*(?:\"|\x27)?" + REPOS_PATH, cmd):
    block("BLOCKED: that redirect would write into repos/.\n\n" + WRITE_HINT)

# Destructive or in-place file commands naming a repos/ path.
DESTRUCTIVE = r"rm|rmdir|mv|cp|touch|mkdir|tee|truncate|chmod|chown|ln|dd"
if re.search(CMDPOS + r"(?:sudo\s+)?(?:" + DESTRUCTIVE + r")\b[^\n;&|]*"
             + REPOS_PATH, cmd):
    block("BLOCKED: that command would modify repos/.\n\n" + WRITE_HINT)

# sed -i / perl -i rewrite files in place.
if re.search(CMDPOS + r"(?:sudo\s+)?(?:sed|perl)\b[^\n;&|]*\s-\S*i\S*\b[^\n;&|]*"
             + REPOS_PATH, cmd):
    block("BLOCKED: that in-place edit targets repos/.\n\n" + WRITE_HINT)

# cd into repos/ and then do something that changes it. Reading after a cd -
# `cd repos/backend && git log` - stays fine.
if re.search(CMDPOS + r"cd\s+(?:\"|\x27)?" + REPOS_PATH, cmd):
    if re.search(CMDPOS + r"(?:sudo\s+)?git\s+(?:-\S+\s+)*(?:" + MUTATING + r")\b", cmd) \
       or re.search(CMDPOS + r"(?:sudo\s+)?(?:" + DESTRUCTIVE + r")\b", cmd) \
       or re.search(r">>?\s*[^\s&|]", cmd):
        block("BLOCKED: that would change a repos/ checkout after cd-ing into it.\n\n"
              + WRITE_HINT)

allow()
'
