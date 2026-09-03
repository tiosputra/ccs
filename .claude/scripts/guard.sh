#!/usr/bin/env bash
#
# guard.sh - PreToolUse hook. Enforces the two workspace rules that CLAUDE.md
# can only ask for:
#
#   1. repos/ is read-only. Never write there, and never run a git command
#      that moves those checkouts. All work happens in spaces/<task>/<repo>/,
#      where git add / commit / push are allowed and expected - /pr uses them.
#
#   2. Reference repos are read-only *everywhere*. REFERENCE_REPOS in .env is
#      a comma list of repo aliases kept for reading, questions and analysis
#      only - REFERENCE_REPOS=mobile,partner seals repos/mobile and
#      repos/partner as before, and also seals spaces/<task>/mobile and
#      spaces/<task>/partner, which the rest of the workspace never opens.
#
# `repos/README.md` is the one exception: it is tracked in this repo (the
# gitignore un-ignores it) and describes the roster rather than living inside
# any checkout, so it is writable. Everything at repos/<repo>/... is sealed.
#
# Reads the hook payload as JSON on stdin. Exit 0 allows the call; exit 2
# blocks it and shows stderr to the agent so it can correct course.
#
# Anything unexpected (bad JSON, missing fields, no python3) exits 0. A guard
# that bricks the session on a malformed payload is worse than no guard. The
# same goes for REFERENCE_REPOS: an unreadable .env leaves the list empty and
# the guard falls back to sealing repos/ alone.
#
# Test it by hand:
#   echo '{"tool_name":"Write","tool_input":{"file_path":"repos/backend/x.ts"}}' \
#     | .claude/scripts/guard.sh; echo "exit=$?"
#
# The matching aims to be precise in both directions: a read dressed up as a
# write is a session-wide tax, and every relaxation below is a case where the
# command provably cannot write into a sealed checkout. See `ccs-conventions`
# for the residual cases.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

command -v python3 >/dev/null 2>&1 || exit 0

# Same precedence as every other setting: environment, then .env, then empty.
. "$SCRIPT_DIR/config.sh" 2>/dev/null
cfg_resolve REFERENCE_REPOS "" 2>/dev/null || REFERENCE_REPOS=""

ROOT="$ROOT" REFERENCE_REPOS="${REFERENCE_REPOS:-}" exec python3 -c '
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
SPACES = os.path.join(ROOT, "spaces")
ROSTER = os.path.join(REPOS, "README.md")
tool   = payload.get("tool_name", "")
inp    = payload.get("tool_input") or {}
cwd    = payload.get("cwd") or os.getcwd()

# Reference-only repos: read them, never write them - not in repos/, and not
# in a space either, which is the part repos/ protection alone misses.
REFS = [r.strip() for r in os.environ.get("REFERENCE_REPOS", "").split(",")
        if r.strip()]

def seal_reason(path):
    """Why this path is sealed, or None if it is writable.

    "repos"     - repos/ is the canonical read-only checkout of everything.
    "reference" - a REFERENCE_REPOS worktree inside a space.

    repos/README.md is tracked here and belongs to the workspace, not to a
    checkout, so it stays writable. repos/ itself and everything below it
    does not."""
    if not path:
        return None
    p = path if os.path.isabs(path) else os.path.join(cwd, path)
    p = os.path.realpath(p)
    if p == os.path.realpath(ROSTER):
        return None
    if p == REPOS or p.startswith(REPOS + os.sep):
        return "repos"
    if REFS and p.startswith(SPACES + os.sep):
        # spaces/<task>/<repo>/... - the repo is the second segment.
        parts = p[len(SPACES) + 1:].split(os.sep)
        if len(parts) >= 2 and parts[1] in REFS:
            return "reference"
    return None

def sealed(path):
    return seal_reason(path) is not None

WRITE_HINT = (
    "repos/ is read-only in this workspace (see CLAUDE.md).\n"
    "Work in the task space instead: spaces/<task>/<repo>/... - git add, commit\n"
    "and push are all allowed there.\n"
    "No space yet? Ask the user for the repos and the source branch, then\n"
    "run: .claude/scripts/space.sh add <task> <repos> --from <source-branch>"
)

REF_HINT = (
    "That path is inside a reference-only repo (REFERENCE_REPOS in .env: "
    + ", ".join(REFS) + ").\n"
    "Those repos exist to be read, searched and asked about - never edited,\n"
    "committed, or written to by a generator, in repos/ or in a space.\n"
    "If the change really belongs there, the user has to drop the repo from\n"
    "REFERENCE_REPOS first; that is their call, not yours."
)

def hint(reason):
    return REF_HINT if reason == "reference" else WRITE_HINT

# ---- file-writing tools -------------------------------------------------
if tool in ("Write", "Edit", "NotebookEdit", "MultiEdit"):
    paths = [inp.get(k) for k in ("file_path", "notebook_path", "path")]
    paths += [e.get("file_path") for e in (inp.get("edits") or [])
              if isinstance(e, dict)]
    for path in paths:
        reason = seal_reason(path)
        if reason:
            block("BLOCKED: refusing to write " + str(path) + "\n\n" + hint(reason))
    allow()

if tool != "Bash":
    allow()

cmd = inp.get("command") or ""

# A command position is the start of the line or just after ; && || | & (
# Matching only there keeps quoted prose - grep "git add" CLAUDE.md - from
# tripping the guard.
CMDPOS = r"(?:^|[\n;&|(]|&&|\|\|)\s*"

# git add / commit / push are allowed - inside a space, for a repo that is not
# reference-only. Only the sealed paths below are refused.
# ---- sealed paths, shell edition ----------------------------------------
# Any sealed path written as a bare relative path, or as an absolute path.
# repos/README.md is carved out so the roster stays editable; a lookalike
# such as repos/README.md.bak is not.
REPOS_PATH = (r"(?:" + re.escape(REPOS) + r"|(?<![\w./-])repos)"
              r"/(?!README\.md(?![\w./-]))\S+")

# spaces/<task>/<reference-repo> and anything under it. `(?![\w.-])` keeps a
# space worktree named mobile-app out of it when the reference repo is mobile.
if REFS:
    SPACE_REF_PATH = (r"(?:" + re.escape(SPACES) + r"|(?<![\w./-])spaces)"
                      r"/[^/\s]+/(?:" + "|".join(re.escape(r) for r in REFS)
                      + r")(?![\w.-])\S*")
    SEALED_PATH = r"(?:" + REPOS_PATH + r"|" + SPACE_REF_PATH + r")"
else:
    SEALED_PATH = REPOS_PATH

def hint_for_text(text):
    """Which rule a matched path text fell under. Text, not resolved path:
    the regex checks match on how the command was written."""
    t = text.strip("\"\x27")
    if re.match(r"(?:" + re.escape(SPACES) + r"|spaces)/", t):
        return REF_HINT
    return WRITE_HINT

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
                   + r"(?P<path>" + SEALED_PATH + r")"
                   + r"(?:\"|\x27)?\s+(?:-\S+\s+)*(?P<sub>\S+)(?P<rest>[^\n;&|]*)")
GIT_PLAIN = re.compile(CMDPOS + r"(?:sudo\s+)?git\s+(?:-\S+\s+)*(\S+)([^\n;&|]*)")

for m in GIT_C.finditer(cmd):
    if git_call_mutates(m.group("sub"), m.group("rest")):
        block("BLOCKED: that git command would mutate a sealed checkout: "
              + m.group("path") + "\n\n" + hint_for_text(m.group("path")))

# ---- redirections -------------------------------------------------------
# A redirect operator is >, >>, N>, &>. It is never -> or =>, so an ASCII arrow
# in prose - "spaces/x/backend -> repos/backend" - is not a redirect.
REDIRECT = re.compile(r"(?<![-=])(?:\d+)?>>?\s*(?:\"|\x27)?(&\d+|&-|[^\s;&|<>()\"\x27]+)")

def redirect_reason(target, base):
    """Why this redirect is refused, or None if it lands somewhere writable."""
    if target.startswith("&"):
        return None                        # fd duplication writes no file
    if target.startswith("/dev/"):
        return None                        # /dev/null, /dev/stderr, /dev/fd/N
    p = target if os.path.isabs(target) else os.path.join(base, target)
    return seal_reason(p)

for m in REDIRECT.finditer(cmd):
    reason = redirect_reason(m.group(1), cwd)
    if reason:
        block("BLOCKED: that redirect would write into a sealed checkout: "
              + m.group(1) + "\n\n" + hint(reason))

# Destructive or in-place file commands naming a sealed path.
DESTRUCTIVE = r"rm|rmdir|mv|cp|touch|mkdir|tee|truncate|chmod|chown|ln|dd"
m = re.search(CMDPOS + r"(?:sudo\s+)?(?:" + DESTRUCTIVE + r")\b[^\n;&|]*"
              + r"(" + SEALED_PATH + r")", cmd)
if m:
    block("BLOCKED: that command would modify a sealed checkout: " + m.group(1)
          + "\n\n" + hint_for_text(m.group(1)))

# sed -i / perl -i rewrite files in place.
m = re.search(CMDPOS + r"(?:sudo\s+)?(?:sed|perl)\b[^\n;&|]*\s-\S*i\S*\b[^\n;&|]*"
              + r"(" + SEALED_PATH + r")", cmd)
if m:
    block("BLOCKED: that in-place edit targets a sealed checkout: " + m.group(1)
          + "\n\n" + hint_for_text(m.group(1)))

# cd into a sealed checkout and then do something that changes it. Reading
# after a cd - `cd repos/backend && git log`, or `cd repos/backend && ls
# 2>/dev/null` - stays fine: a redirect only counts if its target resolves
# inside a sealed checkout.
into = re.search(CMDPOS + r"cd\s+(?:\"|\x27)?(" + SEALED_PATH + r")", cmd)
if into:
    base = into.group(1).strip("\"\x27")
    base = base if os.path.isabs(base) else os.path.join(cwd, base)
    mutating_git = any(git_call_mutates(m.group(1), m.group(2))
                       for m in GIT_PLAIN.finditer(cmd))
    if mutating_git \
       or re.search(CMDPOS + r"(?:sudo\s+)?(?:" + DESTRUCTIVE + r")\b", cmd) \
       or any(redirect_reason(m.group(1), base) for m in REDIRECT.finditer(cmd)):
        block("BLOCKED: that would change a sealed checkout after cd-ing into it.\n\n"
              + hint_for_text(into.group(1)))

allow()
'
