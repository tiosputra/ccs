#!/usr/bin/env bash
#
# guard.sh - PreToolUse hook. Enforces the workspace rules that CLAUDE.md can
# only ask for:
#
#   1. repos/<repo> is sealed unless a task owns it. A checkout is owned by an
#      in-place task while its HEAD is that task's branch AND the task's
#      metadata (.claude/state/tasks/<task>, see tasklib.sh) lists the repo -
#      both, or it stays sealed. The checkout's own root and its .git are
#      sealed even then.
#
#   2. In an owned checkout, git may add, commit, and push the task branch -
#      and nothing else that moves history. checkout, switch, reset, rebase,
#      merge, pull and the like are refused (only task.sh moves branches), and
#      a push to any other ref is refused: work reaches the base branch through
#      a pull request, never directly.
#
#   3. Reference repos are read-only *everywhere*. REFERENCE_REPOS in .env is
#      a comma list of repo aliases kept for reading, questions and analysis
#      only - REFERENCE_REPOS=mobile,partner seals repos/mobile and
#      repos/partner, whatever a task claims, and also spaces/<task>/mobile and
#      spaces/<task>/partner.
#
# A space's worktrees (spaces/<task>/<repo>) are writable, git included.
#
# `repos/README.md` is the one exception under repos/: it is tracked in this
# repo (the gitignore un-ignores it) and describes the roster rather than
# living inside any checkout, so it is writable.
#
# Reads the hook payload as JSON on stdin. Exit 0 allows the call; exit 2
# blocks it and shows stderr to the agent so it can correct course.
#
# Anything unexpected in the payload (bad JSON, missing fields, no python3)
# exits 0. A guard that bricks the session on a malformed payload is worse
# than no guard. Ownership is the opposite: any doubt about who holds a
# checkout - unreadable HEAD, unreadable metadata - leaves it sealed.
#
# Test it by hand:
#   echo '{"tool_name":"Write","tool_input":{"file_path":"repos/api/x.ts"}}' \
#     | .claude/scripts/guard.sh; echo "exit=$?"
#
# The matching aims to be precise in both directions: a read dressed up as a
# write is a session-wide tax, and every relaxation below is a case where the
# command provably cannot write into a sealed checkout. See `ccs-conventions`
# for the residual cases, and guard-test.sh for the pinned behaviour.

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
if not isinstance(payload, dict):
    allow()

ROOT   = os.path.realpath(os.environ["ROOT"])
REPOS  = os.path.join(ROOT, "repos")
SPACES = os.path.join(ROOT, "spaces")
STATE  = os.path.join(ROOT, ".claude", "state", "tasks")
ROSTER = os.path.join(REPOS, "README.md")
tool   = payload.get("tool_name", "")
inp    = payload.get("tool_input") or {}
cwd    = payload.get("cwd") or os.getcwd()

# Reference-only repos: read them, never write them - not in repos/, and not
# in a space either.
REFS = [r.strip() for r in os.environ.get("REFERENCE_REPOS", "").split(",")
        if r.strip()]

# ---- ownership ------------------------------------------------------------

def read_head(repo_dir):
    """The branch repo_dir has checked out, or None: detached, unreadable, or
    not a checkout. .git may be a directory or a gitdir: pointer file."""
    try:
        g = os.path.join(repo_dir, ".git")
        if os.path.isfile(g):
            line = open(g).read().strip()
            if not line.startswith("gitdir:"):
                return None
            gd = line[len("gitdir:"):].strip()
            if not os.path.isabs(gd):
                gd = os.path.join(repo_dir, gd)
        else:
            gd = g
        head = open(os.path.join(gd, "HEAD")).read().strip()
        if head.startswith("ref: refs/heads/"):
            return head[len("ref: refs/heads/"):]
    except Exception:
        pass
    return None

_owner = {}
def owner(repo):
    """(task, branch) of the in-place task holding repos/<repo>, or None.

    Held means the checkout HEAD is the task branch and the task metadata
    lists the repo. Either alone is not enough: a branch switched by hand is
    not a task, and metadata whose checkout moved on is not holding anything.
    Any error reads as not held, which keeps the checkout sealed."""
    if repo in _owner:
        return _owner[repo]
    found = None
    try:
        branch = read_head(os.path.join(REPOS, repo))
        if branch and os.path.isdir(STATE):
            for name in sorted(os.listdir(STATE)):
                fields, repos_in = {}, set()
                with open(os.path.join(STATE, name)) as fh:
                    for line in fh:
                        f = line.rstrip("\n").split("\t")
                        if f[0] == "base" and len(f) > 1:
                            repos_in.add(f[1])
                        elif len(f) > 1:
                            fields.setdefault(f[0], f[1])
                if (fields.get("isolation") == "inplace"
                        and fields.get("branch") == branch
                        and repo in repos_in):
                    found = (name, branch)
                    break
    except Exception:
        found = None
    _owner[repo] = found
    return found

def resolve(path, base):
    p = path if os.path.isabs(path) else os.path.join(base, path)
    return os.path.realpath(p)

def checkout_of(p):
    """What a resolved path is inside, as (kind, detail):
    ("repos", None)        sealed - repos/ itself, or a checkout no task holds
    ("reference", None)    sealed - a REFERENCE_REPOS checkout, anywhere
    ("owned", (task, br))  repos/<repo> held by an in-place task
    (None, None)           anywhere else, a space worktree included"""
    if p == REPOS or p.startswith(REPOS + os.sep):
        rel = p[len(REPOS) + 1:] if p != REPOS else ""
        repo = rel.split(os.sep)[0] if rel else ""
        if not repo:
            return ("repos", None)
        if repo in REFS:
            return ("reference", None)
        o = owner(repo)
        return ("owned", o) if o else ("repos", None)
    if REFS and p.startswith(SPACES + os.sep):
        parts = p[len(SPACES) + 1:].split(os.sep)
        if len(parts) >= 2 and parts[1] in REFS:
            return ("reference", None)
    return (None, None)

def seal_reason(path, base):
    """Why writing this path is refused, or None if it is writable.

    Inside an owned checkout, files are writable - but not the checkout
    root itself, and never anything under its .git."""
    if not path:
        return None
    p = resolve(path, base)
    if p == os.path.realpath(ROSTER):
        return None
    kind, _ = checkout_of(p)
    if kind in ("repos", "reference"):
        return kind
    if kind == "owned":
        parts = p[len(REPOS) + 1:].split(os.sep)
        if len(parts) < 2 or parts[1] == ".git":
            return "repos"
    return None

WRITE_HINT = (
    "That checkout is sealed: repos/<repo> is writable only while an in-place\n"
    "task holds it (see CLAUDE.md).\n"
    "Find where the task works: .claude/scripts/task.sh where <task> <repo>\n"
    "No task yet? Ask the user for the repos and the source branch, then run:\n"
    "  .claude/scripts/task.sh start <task> <repos> --from <source-branch>\n"
    "(add --space to work in a worktree under spaces/ instead)."
)

REF_HINT = (
    "That path is inside a reference-only repo (REFERENCE_REPOS in .env: "
    + ", ".join(REFS) + ").\n"
    "Those repos exist to be read, searched and asked about - never edited,\n"
    "committed, or written to by a generator, in repos/ or in a space.\n"
    "If the change really belongs there, the user has to drop the repo from\n"
    "REFERENCE_REPOS first; that is their call, not yours."
)

def owned_hint(detail):
    task, branch = detail
    return (
        "repos/ checkout held by task " + task + " on " + branch + ".\n"
        "In it, git may add, commit, and push " + branch + " - nothing else that\n"
        "moves history. Branches move only through task.sh, and work reaches the\n"
        "base branch only through a pull request (/pr), never by a direct push."
    )

def hint(reason):
    return REF_HINT if reason == "reference" else WRITE_HINT

# ---- file-writing tools -------------------------------------------------
if tool in ("Write", "Edit", "NotebookEdit", "MultiEdit"):
    paths = [inp.get(k) for k in ("file_path", "notebook_path", "path")]
    paths += [e.get("file_path") for e in (inp.get("edits") or [])
              if isinstance(e, dict)]
    for path in paths:
        if not isinstance(path, str):
            continue
        reason = seal_reason(path, cwd)
        if reason:
            block("BLOCKED: refusing to write " + path + "\n\n" + hint(reason))
    allow()

if tool != "Bash":
    allow()

cmd = inp.get("command") or ""
if not isinstance(cmd, str):
    allow()

# A command position is the start of the line or just after ; && || | & (
# Matching only there keeps quoted prose - grep "git add" CLAUDE.md - from
# tripping the guard.
CMDPOS = r"(?:^|[\n;&|(]|&&|\|\|)\s*"

# ---- where plain commands run -------------------------------------------
# A command that cds first runs there; otherwise it runs in the session cwd.
# Plain git calls, redirects and in-place edits are judged against that
# directory, so `git commit` from inside a sealed checkout is refused whether
# the cd is in this command or happened earlier in the session.
CD = re.search(CMDPOS + r"cd\s+(?:\"|\x27)?([^\s\"\x27;&|]+)", cmd)
EFF = resolve(CD.group(1).strip("\"\x27"), cwd) if CD else os.path.realpath(cwd)
EFF_KIND, EFF_DETAIL = checkout_of(EFF)

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

# In a checkout an in-place task holds, only these may change it. Anything
# else in ALWAYS_MUTATING/DUAL moves history or the branch and is refused.
OWNED_OK = ("add", "commit", "rm", "mv", "restore", "apply", "fetch", "stash", "push")

def push_violation(rest, branch):
    """Why this push is refused from an owned checkout, or None. Only the task
    branch may be pushed: bare `git push` (HEAD is the task branch), HEAD, or
    refspecs whose destination is the task branch."""
    toks = rest.split()
    for t in toks:
        if t in ("--all", "--mirror", "--tags", "--delete", "-d", "--prune"):
            return "git push " + t + " reaches beyond the task branch"
    args = [t for t in toks if not t.startswith("-")]
    for spec in args[1:]:
        spec = spec.lstrip("+")
        src, dst = spec.split(":", 1) if ":" in spec else (spec, spec)
        if src == "" or dst == "":
            return "a push of an empty ref (" + spec + ") deletes a remote branch"
        if dst.startswith("refs/heads/"):
            dst = dst[len("refs/heads/"):]
        if dst not in (branch, "HEAD"):
            return "only " + branch + " may be pushed from this checkout, not " + dst
    return None

def owned_violation(sub, rest, detail):
    if not git_call_mutates(sub, rest):
        return None
    if sub == "push":
        return push_violation(rest, detail[1])
    if sub in OWNED_OK:
        return None
    return "git " + sub + " moves history or the branch"

# A redirect is shell plumbing, not an argument to git: `2>&1`, `>out`, and
# `> out` with its target in the next word. Left in, `git push origin HEAD 2>&1`
# reads as a push to a ref named `2>`. The targets are judged on their own below.
REDIRECT_WORD = re.compile(r"^(?:\d*>>?|&>>?|\d*<)(.*)$")

def without_redirects(rest):
    out, target_next = [], False
    for t in rest.split():
        if target_next:
            target_next = False
            continue
        m = REDIRECT_WORD.match(t)
        if m:
            target_next = m.group(1) == ""
            continue
        out.append(t)
    return " ".join(out)

def judge_git(kind, detail, sub, rest, where):
    rest = without_redirects(rest)
    if kind in ("repos", "reference"):
        if git_call_mutates(sub, rest):
            block("BLOCKED: that git command would change a sealed checkout: "
                  + where + "\n\n" + hint(kind))
    elif kind == "owned":
        why = owned_violation(sub, rest, detail)
        if why:
            block("BLOCKED: " + why + " (" + where + ").\n\n" + owned_hint(detail))

# A git call's arguments run to the next ; && || | or newline. The & of a >& or
# &> redirect belongs to the call, so `git push origin HEAD 2>&1 main` still
# shows `main` to the push check instead of ending at `2>`.
GIT_REST = r"(?:>&|&>|[^\n;&|])*"
GIT_C = re.compile(CMDPOS + r"(?:sudo\s+)?git\s+(?:-\S+\s+)*-C\s+(?:\"|\x27)?"
                   r"(?P<path>[^\s\"\x27]+)"
                   r"(?:\"|\x27)?\s+(?:-\S+\s+)*(?P<sub>\S+)(?P<rest>" + GIT_REST + r")")
GIT_PLAIN = re.compile(CMDPOS + r"(?:sudo\s+)?git\s+(?:-\S+\s+)*(\S+)(" + GIT_REST + r")")

for m in GIT_C.finditer(cmd):
    kind, detail = checkout_of(resolve(m.group("path"), EFF))
    judge_git(kind, detail, m.group("sub"), m.group("rest"), m.group("path"))

if EFF_KIND:
    for m in GIT_PLAIN.finditer(cmd):
        if re.search(r"\s-C\s", m.group(0)):
            continue                          # a -C call, judged above
        judge_git(EFF_KIND, EFF_DETAIL, m.group(1), m.group(2), os.path.relpath(EFF, ROOT))

# ---- redirections -------------------------------------------------------
# A redirect operator is >, >>, N>, &>. It is never -> or =>, so an ASCII arrow
# in prose - "spaces/x/api -> repos/api" - is not a redirect.
REDIRECT = re.compile(r"(?<![-=])(?:\d+)?>>?\s*(?:\"|\x27)?(&\d+|&-|[^\s;&|<>()\"\x27]+)")

def redirect_reason(target):
    """Why this redirect is refused, or None if it lands somewhere writable."""
    if target.startswith("&"):
        return None                        # fd duplication writes no file
    if target.startswith("/dev/"):
        return None                        # /dev/null, /dev/stderr, /dev/fd/N
    if "$" in target or "`" in target:
        return None                        # unexpanded - its value is not known here
    return seal_reason(target, EFF)

for m in REDIRECT.finditer(cmd):
    reason = redirect_reason(m.group(1))
    if reason:
        block("BLOCKED: that redirect would write into a sealed checkout: "
              + m.group(1) + "\n\n" + hint(reason))

# ---- file commands --------------------------------------------------------
# Destructive or in-place commands are judged per path they name, by the same
# seal_reason the file tools use - so they work inside an owned checkout and
# a space, and are refused against a sealed one.
DESTRUCTIVE = r"rm|rmdir|mv|cp|touch|mkdir|tee|truncate|chmod|chown|ln|dd"
SEGMENT = re.compile(r"[^\n;&|]+")
IS_DESTRUCTIVE = re.compile(r"^\s*(?:sudo\s+)?(?:" + DESTRUCTIVE + r")\b")
IS_INPLACE = re.compile(r"^\s*(?:sudo\s+)?(?:sed|perl)\b[^\n]*\s-\S*i")
RELATIVE_SEALABLE = re.compile(r"^(?:\.{1,2}/)*(?:repos|spaces)(?:/|$)")

def path_args(seg):
    """The arguments of one command that name a path worth judging: absolute
    paths, and relative ones that start at repos/ or spaces/. A word merely
    containing "repos" - ws/repos, myrepos - is not one, and an argument with
    an unexpanded $VAR or backtick cannot be resolved honestly, so it is left
    alone rather than guessed at."""
    for tok in seg.split()[1:]:
        t = tok.strip("\"\x27")
        if not t or t.startswith("-") or "$" in t or "`" in t:
            continue
        if t.startswith("/") or RELATIVE_SEALABLE.match(t):
            yield t

for seg in SEGMENT.findall(cmd):
    if not (IS_DESTRUCTIVE.match(seg) or IS_INPLACE.match(seg)):
        continue
    for arg in path_args(seg):
        reason = seal_reason(arg, EFF)
        if reason:
            block("BLOCKED: that command would modify a sealed checkout: "
                  + arg + "\n\n" + hint(reason))
    # Relative paths from inside a sealed checkout: `cd repos/api && rm -rf src`.
    if EFF_KIND in ("repos", "reference"):
        block("BLOCKED: that would change a sealed checkout from inside it ("
              + os.path.relpath(EFF, ROOT) + ").\n\n" + hint(EFF_KIND))

allow()
'
