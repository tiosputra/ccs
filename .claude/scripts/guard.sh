#!/usr/bin/env bash
#
# guard.sh - PreToolUse hook. Enforces the workspace rules that CLAUDE.md can
# only ask for:
#
#   1. Checkouts are writable. repos/<repo> is treated like a space's
#      worktrees (spaces/<task>/<repo>): files and git alike, whether or not a
#      task holds it.
#
#   2. A source branch is never deleted. In any checkout, in repos/ or in a
#      space, a git call that deletes or renames a source branch - the local
#      branch, its remote-tracking ref, or the branch on the remote - is
#      refused, and so is a push with --mirror or --prune, which can delete one
#      without naming it. A repo's source branches, each without its remote
#      prefix, are:
#        - every base a task records for it  (base<TAB><repo><TAB><ref>)
#        - every branch a task will return its checkout to  (home<TAB>...)
#        - TASK_DEFAULT_BASE
#        - the remote's default branch  (refs/remotes/origin/HEAD)
#      Task metadata is .claude/state/tasks/<task> (see tasklib.sh). If any of
#      it cannot be read, the source branches are unknown and every branch of
#      the repo is protected until it can be.
#      For the same reason repos/ itself, a checkout's root in repos/ and
#      everything inside its .git are never written or removed directly: they
#      hold every branch. Git writes its own files there as usual.
#
#   3. Reference repos are read-only *everywhere*. REFERENCE_REPOS in .env is
#      a comma list of repo aliases kept for reading, questions and analysis
#      only - REFERENCE_REPOS=mobile,partner seals repos/mobile and
#      repos/partner, and also spaces/<task>/mobile and spaces/<task>/partner.
#
# Reads the hook payload as JSON on stdin. Exit 0 allows the call; exit 2
# blocks it and shows stderr to the agent so it can correct course.
#
# Anything unexpected in the payload (bad JSON, missing fields, no python3)
# exits 0. A guard that bricks the session on a malformed payload is worse
# than no guard. Source branches are the opposite: any doubt about which they
# are protects them all.
#
# Test it by hand:
#   echo '{"tool_name":"Bash","tool_input":{"command":"git -C repos/api branch -D main"}}' \
#     | .claude/scripts/guard.sh; echo "exit=$?"
#
# The matching aims to be precise in both directions: a read or an ordinary
# write refused is a session-wide tax, and every relaxation below is a case
# where the command provably cannot delete a source branch or write into a
# reference repo. See `ccs-conventions` for the residual cases, and
# guard-test.sh for the pinned behaviour.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

command -v python3 >/dev/null 2>&1 || exit 0

# Same precedence as every other setting: environment, then .env, then built-in.
. "$SCRIPT_DIR/config.sh" 2>/dev/null
cfg_resolve REFERENCE_REPOS "" 2>/dev/null || REFERENCE_REPOS=""
cfg_resolve_renamed TASK_DEFAULT_BASE SPACE_DEFAULT_BASE origin/main 2>/dev/null \
  || TASK_DEFAULT_BASE=origin/main

ROOT="$ROOT" REFERENCE_REPOS="${REFERENCE_REPOS:-}" \
  TASK_DEFAULT_BASE="${TASK_DEFAULT_BASE:-origin/main}" exec python3 -c '
import fnmatch, json, os, re, sys

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
DEFAULT_BASE = os.environ.get("TASK_DEFAULT_BASE", "")
tool   = payload.get("tool_name", "")
inp    = payload.get("tool_input") or {}
cwd    = payload.get("cwd") or os.getcwd()

# Reference-only repos: read them, never write them - not in repos/, and not
# in a space either.
REFS = [r.strip() for r in os.environ.get("REFERENCE_REPOS", "").split(",")
        if r.strip()]

GLOB = re.compile(r"[*?\[]")

# ---- a checkout and its branches -----------------------------------------

def git_dir(checkout):
    """The git directory of a checkout, or None. .git may be a directory or a
    gitdir: pointer file."""
    try:
        g = os.path.join(checkout, ".git")
        if os.path.isfile(g):
            line = open(g).read().strip()
            if not line.startswith("gitdir:"):
                return None
            gd = line[len("gitdir:"):].strip()
            if not os.path.isabs(gd):
                gd = os.path.join(checkout, gd)
            return os.path.realpath(gd)
        return g if os.path.isdir(g) else None
    except Exception:
        return None

def read_head(checkout):
    """The branch a checkout has checked out, or None: detached, unreadable,
    or not a checkout."""
    try:
        head = open(os.path.join(git_dir(checkout), "HEAD")).read().strip()
        if head.startswith("ref: refs/heads/"):
            return head[len("ref: refs/heads/"):]
    except Exception:
        pass
    return None

def remotes(repo):
    names = {"origin"}
    gd = git_dir(os.path.join(REPOS, repo))
    try:
        names |= set(os.listdir(os.path.join(gd, "refs", "remotes")))
    except Exception:
        pass
    return names

def branch_name(ref, rems):
    """A ref as the branch it names: refs/heads/, refs/remotes/ and a leading
    remote dropped - origin/main, refs/heads/main and main are all main."""
    ref = ref.strip().lstrip("+")
    if ref.startswith("refs/heads/"):
        return ref[len("refs/heads/"):]
    if ref.startswith("refs/remotes/"):
        return ref[len("refs/remotes/"):].partition("/")[2]
    first, _, rest = ref.partition("/")
    return rest if rest and first in rems else ref

def metadata_files():
    """Every task metadata file, current and legacy (spaces/<task>/.space)."""
    files = []
    if os.path.isdir(STATE):
        files += [os.path.join(STATE, n) for n in sorted(os.listdir(STATE))]
    if os.path.isdir(SPACES):
        for n in sorted(os.listdir(SPACES)):
            legacy = os.path.join(SPACES, n, ".space")
            if os.path.isfile(legacy):
                files.append(legacy)
    return files

_sources = {}
def source_branches(repo):
    """The source branches of repo, or None when they cannot be known - which
    protects every branch."""
    if repo in _sources:
        return _sources[repo]
    rems = remotes(repo)
    names = set()
    try:
        if DEFAULT_BASE:
            names.add(branch_name(DEFAULT_BASE, rems))
        gd = git_dir(os.path.join(REPOS, repo))
        if gd:
            try:
                h = open(os.path.join(gd, "refs", "remotes", "origin", "HEAD")).read().strip()
                if h.startswith("ref: "):
                    names.add(branch_name(h[len("ref: "):], rems))
            except OSError:
                pass
        for path in metadata_files():
            if os.path.isdir(path):
                continue
            with open(path) as fh:
                for line in fh:
                    f = line.rstrip("\n").split("\t")
                    if f[0] in ("base", "home") and len(f) > 2 and f[1] == repo:
                        names.add(branch_name(f[2], rems))
        found = names
    except Exception:
        found = None
    _sources[repo] = found
    return found

# ---- where a path is ------------------------------------------------------

def resolve(path, base):
    p = path if os.path.isabs(path) else os.path.join(base, path)
    return os.path.realpath(p)

def checkout_of(p):
    """What a resolved path is inside, as (kind, detail):
    ("reference", None)            a REFERENCE_REPOS checkout, anywhere
    ("checkout", (repo, dir))      any other repos/<repo> or spaces/<task>/<repo>
    ("repos", None)                repos/ itself
    (None, None)                   anywhere else"""
    if p == REPOS:
        return ("repos", None)
    if p.startswith(REPOS + os.sep):
        repo = p[len(REPOS) + 1:].split(os.sep)[0]
        if repo in REFS:
            return ("reference", None)
        return ("checkout", (repo, os.path.join(REPOS, repo)))
    if p.startswith(SPACES + os.sep):
        parts = p[len(SPACES) + 1:].split(os.sep)
        if len(parts) >= 2:
            if parts[1] in REFS:
                return ("reference", None)
            return ("checkout", (parts[1], os.path.join(SPACES, parts[0], parts[1])))
    return (None, None)

def is_checkout_name(pattern):
    """Whether a repos/ entry - or a glob over them - names a real checkout."""
    try:
        names = [n for n in os.listdir(REPOS)
                 if os.path.exists(os.path.join(REPOS, n, ".git"))]
    except Exception:
        return bool(GLOB.search(pattern))
    if GLOB.search(pattern):
        return any(fnmatch.fnmatchcase(n, pattern) for n in names)
    return pattern in names

def seal_reason(path, base):
    """Why writing this path is refused, or None if it is writable.

    repos/ itself, a checkout root in repos/, and anything under its .git hold
    every branch of the repo, so they are never written directly. A glob that a
    shell would expand to one of them counts: repos/*, repos/<repo>/.*"""
    if not path:
        return None
    p = resolve(path, base)
    if p == os.path.realpath(ROSTER):
        return None
    kind, _ = checkout_of(p)
    if kind in ("reference", "repos"):
        return "reference" if kind == "reference" else "branches"
    if kind == "checkout" and p.startswith(REPOS + os.sep):
        parts = p[len(REPOS) + 1:].split(os.sep)
        if len(parts) == 1:
            return "branches" if is_checkout_name(parts[0]) else None
        top = parts[1]
        if top == ".git":
            return "branches"
        # A shell glob reaches a dotfile only when it starts with a dot.
        if GLOB.search(top) and top.startswith(".") and fnmatch.fnmatchcase(".git", top):
            return "branches"
    return None

BRANCHES_HINT = (
    "repos/, a checkout root in repos/ and its .git hold every branch of the repo,\n"
    "the source branch included, so they are never written or removed directly.\n"
    "Everything else in a checkout is writable, and git itself writes there as usual."
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
    return REF_HINT if reason == "reference" else BRANCHES_HINT

def source_hint(names):
    if names is None:
        return ("Task metadata under .claude/state/tasks could not be read, so this\n"
                "repo\x27s source branches are unknown and no branch may be deleted or\n"
                "renamed until it can be.")
    return ("A source branch is never deleted - not locally, not on a remote, not by\n"
            "renaming it. This repo\x27s source branches: " + ", ".join(sorted(names)) + "\n"
            "(task bases, the branches tasks return their checkouts to,\n"
            "TASK_DEFAULT_BASE, and the remote\x27s default branch).\n"
            "Any other branch may be deleted or renamed.")

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
# Plain git calls, redirects and file commands are judged against that
# directory, so `git branch -D main` from inside a checkout is judged whether
# the cd is in this command or happened earlier in the session.
CD = re.search(CMDPOS + r"cd\s+(?:\"|\x27)?([^\s\"\x27;&|]+)", cmd)
EFF = resolve(CD.group(1).strip("\"\x27"), cwd) if CD else os.path.realpath(cwd)
EFF_KIND, EFF_DETAIL = checkout_of(EFF)
IN_REPOS = EFF == REPOS or EFF.startswith(REPOS + os.sep)

# ---- git subcommands ----------------------------------------------------
# In a reference repo nothing that changes the checkout runs. These are the
# verbs that change one no matter how they are invoked...
ALWAYS_MUTATING = ("add|commit|checkout|switch|merge|rebase|reset|revert|restore|"
                   "cherry-pick|apply|am|push|pull|fetch|clean|rm|mv|gc|prune|"
                   "update-ref")

# ...and the verbs with both a read-only and a mutating form. `git branch
# --list` and `git worktree list` only report; `git branch -d` and
# `git worktree add` do not.
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

SHORT = re.compile(r"^-[A-Za-z]+$")

def doomed_refs(sub, rest, checkout):
    """The refs this git call deletes or renames away, as written."""
    toks = [t.strip("\"\x27") for t in rest.split()]
    short = [t[1:] for t in toks if SHORT.match(t)]
    pos = [t for t in toks if t and not t.startswith("-")]
    if sub == "branch":
        if "--delete" in toks or any(set(s) & set("dD") for s in short):
            return pos
        if "--move" in toks or any(set(s) & set("mM") for s in short):
            if len(pos) >= 2:
                return pos[:1]
            return [read_head(checkout) or ""]
        return []
    if sub == "push":
        deleting = "--delete" in toks or any("d" in s for s in short)
        specs = pos[1:] if len(pos) > 1 else pos     # the first names the remote
        out = []
        for spec in specs:
            s = spec.lstrip("+")
            if s.startswith(":"):
                out.append(s[1:])
            elif deleting:
                out.append(s.rpartition(":")[2])
        return out
    if sub == "update-ref":
        if "-d" in toks or any("d" in s for s in short):
            return pos[:1]
        return []
    return []

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
            block("BLOCKED: that git command would change a reference-only repo: "
                  + where + "\n\n" + REF_HINT)
        return
    if kind != "checkout":
        return
    repo, checkout = detail
    if sub == "push" and re.search(r"(?:^|\s)--(?:mirror|prune)\b", rest):
        block("BLOCKED: git push --mirror/--prune can delete branches on the remote,\n"
              "a source branch among them (" + where + ").\n\n"
              + source_hint(source_branches(repo)))
    doomed = doomed_refs(sub, rest, checkout)
    if not doomed:
        return
    names = source_branches(repo)
    rems = remotes(repo)
    for ref in doomed:
        b = branch_name(ref, rems)
        if not b:
            continue
        if names is None or b in names:
            block("BLOCKED: that git command would delete or rename the source branch "
                  + b + " (" + where + ").\n\n" + source_hint(names))

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
        block("BLOCKED: that redirect would write into " + m.group(1)
              + "\n\n" + hint(reason))

# ---- file commands --------------------------------------------------------
# Destructive or in-place commands are judged per path they name, by the same
# seal_reason the file tools use.
DESTRUCTIVE = r"rm|rmdir|mv|cp|touch|mkdir|tee|truncate|chmod|chown|ln|dd"
SEGMENT = re.compile(r"[^\n;&|]+")
IS_DESTRUCTIVE = re.compile(r"^\s*(?:sudo\s+)?(?:" + DESTRUCTIVE + r")\b")
IS_INPLACE = re.compile(r"^\s*(?:sudo\s+)?(?:sed|perl)\b[^\n]*\s-\S*i")
RELATIVE_SEALABLE = re.compile(r"^(?:\.{1,2}/)*(?:repos|spaces)(?:/|$)")

def path_args(seg):
    """The arguments of one command that name a path worth judging: absolute
    paths, relative ones that start at repos/ or spaces/, and - for a command
    running inside repos/ - every relative one, since `rm -rf .git` there names
    a checkout\x27s branches. A word merely containing "repos" - ws/repos,
    myrepos - is not one, and an argument with an unexpanded $VAR or backtick
    cannot be resolved honestly, so it is left alone rather than guessed at."""
    for tok in seg.split()[1:]:
        t = tok.strip("\"\x27")
        if not t or t.startswith("-") or "$" in t or "`" in t:
            continue
        if t.startswith("/") or RELATIVE_SEALABLE.match(t) or IN_REPOS:
            yield t

for seg in SEGMENT.findall(cmd):
    if not (IS_DESTRUCTIVE.match(seg) or IS_INPLACE.match(seg)):
        continue
    for arg in path_args(seg):
        reason = seal_reason(arg, EFF)
        if reason:
            block("BLOCKED: that command would modify " + arg + "\n\n" + hint(reason))
    # Relative paths from inside a reference repo: `cd repos/partner && rm -rf src`.
    if EFF_KIND == "reference":
        block("BLOCKED: that would change a reference-only repo from inside it ("
              + os.path.relpath(EFF, ROOT) + ").\n\n" + REF_HINT)

allow()
'
