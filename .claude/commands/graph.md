---
description: Build code-review-graph graphs of checkouts and spaces, and show what a task's change touches
argument-hint: "[status] | build <repo>|<task>/<repo>|all | review <task>[/<repo>] [--base <ref>] | run <target> <query> [args] | prune"
allowed-tools: Bash(.claude/scripts/graph.sh:*), Read, Grep, Glob
---

## Result

!`.claude/scripts/graph.sh slash $ARGUMENTS`

## What this is

`code-review-graph` parses a repo with tree-sitter into a graph of functions,
classes, calls, imports and tests. It answers the questions a review keeps
asking: what calls this, what does this change reach, which of the changed
functions have no test. It does that without reading the whole codebase.

`graph.sh` is the only way it runs here. Left to itself the tool writes
`.code-review-graph/` into the repo it reads, which is a write into `repos/` or
an extra directory in a space's pull request. The script keeps every graph at
the workspace root, gitignored, laid out like the workspace:

```
.code-review-graph/repos/<repo>/            repos/<repo>
.code-review-graph/spaces/<task>/<repo>/    spaces/<task>/<repo>
```

A graph is derived data: seconds to rebuild (backend ~6s, mobile ~11s on
2026-09-16), so the script always does a full build and never an incremental
update. It builds from a scratch copy of the git index, which gives it two
things the tool cannot do alone. Files not committed yet are in the graph, and
the paths in `.code-review-graphignore` (generated code, migrations, vendored
packages) are never parsed.

```
/graph                                  every checkout and space, and whether its graph is fresh
/graph build backend                    graph repos/backend
/graph build all                        graph every checkout
/graph review fix-promo                 blast radius of each repo in the space against its base
/graph run fix-promo/backend query callers_of applyPromo
/graph prune                            graphs left behind by a space that is gone
```

The first line of the result says which `mode` ran.

## mode: status

`installed` says whether the tool is on the PATH. If it says `no`, give the
install line and stop.

Rows are `graph<TAB>target<TAB>kind<TAB>state<TAB>built<TAB>files<TAB>nodes`.

| state | Meaning | What to say |
|---|---|---|
| `fresh` | Nothing it was built from has changed: HEAD, uncommitted work, untracked files, the ignore file, the tool version | Nothing |
| `stale` | One of those changed | Offer `/graph build <target>`, but only if someone is about to query it. `review` rebuilds on its own |
| `missing` | Never built | Same |
| `orphan` | Its space is gone | Offer `/graph prune` |

Do not rebuild everything unasked. A graph nobody queries is not worth refreshing.

## mode: build

One `built` row per target: files parsed, nodes, how many paths the ignore
file excluded, and where the graph went. An `error` row carries the last lines
of the tool's log, and the previous graph for that target is left in place.
Relay the numbers. Do not retry a failed build with different arguments.

## mode: review

One block per repo in the space:

- `base` is `<sha> <ref> <how>`. `merge-base` means it is the fork point from
  the ref the space was created from, so a rebase onto a newer base still
  compares only this task's work. `recorded` means that ref is gone and the SHA
  saved at `/space add` was used. `given` means `--base` was passed.
- `graph` is `fresh` or `rebuilt`.
- Between `begin summary` and `end summary` is the tool's analysis of the
  changed files: changed functions, affected flows, test gaps, a risk score,
  and the untested functions by name.

**How to use it.** It is a map for the review, not a verdict. The risk score is
a heuristic, so do not quote it as a finding. What earns attention:

- An **untested** function that the change touched is a question for the
  `tdd-workflow` evidence: was it covered by a test this task wrote under
  another name, or is it genuinely untested?
- A high **affected flows** count means the change sits on a shared path. Look
  at the callers before signing off on the change itself:
  `.claude/scripts/graph.sh run <task>/<repo> query callers_of <function>`.

When `/plan-prd` runs this before dispatching reviewers, each reviewer gets its
own repo's block.

## mode: run

Output is the tool's JSON. Queries it accepts:

| query | For |
|---|---|
| `query <pattern> <name>` | `callers_of`, `callees_of`, `importers_of`, `imports_of`, `tests_for`, `children_of`, `inheritors_of`, `file_summary` |
| `impact --base <ref>` | Blast radius of the uncommitted and committed changes since `<ref>` |
| `search <text>` | Find a symbol by name |
| `architecture`, `communities`, `flows` | The shape of an unfamiliar repo |
| `large-functions`, `dead-code` | Candidates, not findings; a callback wired by a framework looks dead |

Anything that writes (`build`, `update`, `forget`, `install`, `serve`) is refused.

`detect-changes` without `--brief` can run to tens of thousands of tokens. On
backend the full flow detail alone measured ~140k. Use `review`, or `impact`
with `--max-results`.

## mode: prune

Lists orphaned graphs and deletes nothing, because this runs before you have
read it. If the user wants them gone, run `.claude/scripts/graph.sh prune`.
`/space remove` already drops a space's graphs as it tears the space down, so
orphans only come from a space removed by hand.

## The MCP servers

`.mcp.json` at the workspace root registers one read-only server per
canonical checkout for `backend`, `payment`, `player` and `sport`, so the graph
can be queried as a tool instead of through `run`. Each one is pinned by
`CRG_DATA_DIR` to the same graph `graph.sh` builds, and `CRG_TOOLS` trims the
tool list from 30 to 6 — none of which write, so a server cannot build a graph
into a checkout.

What that means in practice:

- They serve **`repos/<repo>` only**. A space is a different working tree with
  its own uncommitted work; `review` and `run` cover those.
- They read whatever `graph.sh` last built. A server has no way to refresh
  itself, so if `status` says `stale`, run `/graph build <repo>` — the running
  server picks up the rebuilt database on its next call.
- A new checkout is not registered until someone adds it to `.mcp.json`, and
  Claude Code only reads that file at startup.

## mode: error

Relay the message. It names what exists. Do not guess another target.

## What does not belong here

- **Running `code-review-graph` directly.** Without the script it writes into
  the repo it reads. If an `error` row says the tool wrote inside a checkout,
  stop and tell the user. Never delete from `repos/` yourself.
- **Running `code-review-graph install`.** Measured against `repos/backend` on
  2026-09-16 it writes 15 files into the repo it targets — six MCP configs,
  eight instruction files including an append to that repo's `CLAUDE.md`, and a
  `.gitignore` edit — plus a `PostToolUse` hook that rebuilds the graph bare,
  back inside the checkout. The MCP servers this workspace does use are written
  by hand in the tracked `.mcp.json` at the root.
- **Treating the graph as the code.** It is a parse, and dynamic dispatch,
  framework wiring and reflection are invisible to it. Confirm a surprising
  "no callers" by searching before acting on it.
