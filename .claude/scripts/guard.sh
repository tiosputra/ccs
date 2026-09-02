#!/usr/bin/env bash
#
# guard.sh - PreToolUse hook. Enforces the one workspace rule that CLAUDE.md
# can only ask for:
#
#   repos/ is read-only. Never write there, and never run a git command that
#   moves those checkouts. All work happens in spaces/<task>/<repo>/, where
#   git add / commit / push are allowed and expected - /pr uses them.
#
# `repos/README.md` is the one exception: it is tracked in this repo (the
# gitignore un-ignores it) and describes the roster rather than living inside
# any checkout, so it is writable. Everything at repos/<repo>/... is sealed.
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
#
# The matching aims to be precise in both directions: a read dressed up as a
# write is a session-wide tax, and every relaxation below is a case where the
# command provably cannot write into a checkout. See `ccs-conventions` for the
# residual cases.

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

ROOT   = os.path.realpath(os.environ["ROOT"])
REPOS  = os.path.join(ROOT, "repos")
ROSTER = os.path.join(REPOS, "README.md")
tool   = payload.get("tool_name", "")
inp    = payload.get("tool_input") or {}
cwd    = payload.get("cwd") or os.getcwd()

def sealed(path):
    """True if path is a repos/ location the workspace seals off.

    repos/README.md is tracked here and belongs to the workspace, not to a
    checkout, so it stays writable. repos/ itself and everything below it
    does not."""
    if not path:
        return False
    p = path if os.path.isabs(path) else os.path.join(cwd, path)
    p = os.path.realpath(p)
    if p == os.path.realpath(ROSTER):
        return False
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
        if sealed(inp.get(key)):
            block("BLOCKED: refusing to write " + str(inp[key]) + "\n\n" + WRITE_HINT)
    for e in inp.get("edits") or []:
        if isinstance(e, dict) and sealed(e.get("file_path")):
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
# Any sealed repos/ path written as a bare relative path, or as an absolute
# path. repos/README.md is carved out so the roster stays editable; a lookalike
# such as repos/README.md.bak is not.
REPOS_PATH = (r"(?:" + re.escape(REPOS) + r"|(?<![\w./-])repos)"
              r"/(?!README\.md(?![\w./-]))\S+")

# ---- git subcommands ----------------------------------------------------
# Verbs that move a checkout no matter how they are invoked.
ALWAYS_MUTATING = ("add|commit|checkout|switch|merge|rebase|reset|revert|restore|"
                   "cherry-pick|apply|am|push|pull|fetch|clean|rm|mv|gc|prune")

# Verbs with both a read-only and a mutating form. `git branch --list` and
# `git worktree list` only report; `git branch -d` and `git worktree add` do not.
DUAL = "branch|tag|worktree|stash"

READ_ONLY_FIRST = re.compile(
    r"^\s*(?:--list|-l|--show-current|--merged|--no-merged|--contains|"
    r"--no-contains|--points-at|--format|--sort|--color|--column|--omit-empty|"
    r"-a|--all|-r|--remotes|-v|-vv|-i|--ignore-case|list)\b")

MUTATING_ARG = re.compile(
    r"(?:^|\s)(?:-d|-D|-m|-M|-c|-C|-f|-u|--delete|--move|--copy|--force|"
    r"--create|--set-upstream-to|--unset-upstream|--edit-description|--track|"
    r"--no-track|add|remove|prune|repair|lock|unlock|push|pop|drop|apply|"
    r"clear|save|store|create)\b")

def git_call_mutates(sub, rest):
    if re.match(r"^(?:" + ALWAYS_MUTATING + r")$", sub):
        return True
    if not re.match(r"^(?:" + DUAL + r")$", sub):
        return False
    if not rest.strip():
        # Bare `git branch` / `git tag` list. Bare `git stash` stashes, and
        # bare `git worktree` is a usage error - neither earns the benefit.
        return sub in ("stash", "worktree")
    if MUTATING_ARG.search(rest):
        return True
    return not READ_ONLY_FIRST.match(rest)

GIT_C = re.compile(CMDPOS + r"(?:sudo\s+)?git\s+(?:-\S+\s+)*-C\s+(?:\"|\x27)?"
                   + REPOS_PATH + r"(?:\"|\x27)?\s+(?:-\S+\s+)*(\S+)([^\n;&|]*)")
GIT_PLAIN = re.compile(CMDPOS + r"(?:sudo\s+)?git\s+(?:-\S+\s+)*(\S+)([^\n;&|]*)")

for m in GIT_C.finditer(cmd):
    if git_call_mutates(m.group(1), m.group(2)):
        block("BLOCKED: that git command would mutate a repos/ checkout.\n\n" + WRITE_HINT)

# ---- redirections -------------------------------------------------------
# A redirect operator is >, >>, N>, &>. It is never -> or =>, so an ASCII arrow
# in prose - "spaces/x/backend -> repos/backend" - is not a redirect.
REDIRECT = re.compile(r"(?<![-=])(?:\d+)?>>?\s*(?:\"|\x27)?(&\d+|&-|[^\s;&|<>()\"\x27]+)")

def redirect_writes_into_repos(target, base):
    """True if this redirect could land inside a sealed repos/ path."""
    if target.startswith("&"):
        return False                       # fd duplication writes no file
    if target.startswith("/dev/"):
        return False                       # /dev/null, /dev/stderr, /dev/fd/N
    p = target if os.path.isabs(target) else os.path.join(base, target)
    return sealed(p)

if any(redirect_writes_into_repos(m.group(1), cwd) for m in REDIRECT.finditer(cmd)):
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
# `cd repos/backend && git log`, or `cd repos/backend && ls 2>/dev/null` -
# stays fine: a redirect only counts if its target resolves inside repos/.
into = re.search(CMDPOS + r"cd\s+(?:\"|\x27)?(" + REPOS_PATH + r")", cmd)
if into:
    base = into.group(1).strip("\"\x27")
    base = base if os.path.isabs(base) else os.path.join(cwd, base)
    mutating_git = any(git_call_mutates(m.group(1), m.group(2))
                       for m in GIT_PLAIN.finditer(cmd))
    if mutating_git \
       or re.search(CMDPOS + r"(?:sudo\s+)?(?:" + DESTRUCTIVE + r")\b", cmd) \
       or any(redirect_writes_into_repos(m.group(1), base)
              for m in REDIRECT.finditer(cmd)):
        block("BLOCKED: that would change a repos/ checkout after cd-ing into it.\n\n"
              + WRITE_HINT)

allow()
'
