---
name: team-builder
description: Interactive picker that discovers the agents in .claude/agents/, groups them into domains, has the user select up to five, dispatches them in parallel on one task, and synthesizes agreements and conflicts into a unified report. Use when composing a team of agents, browsing available agent personas, or running several specialist agents in parallel.
metadata:
  origin: community
---

# Team Builder

Interactive menu for browsing and composing agent teams on demand. Works with flat or domain-subdirectory agent collections.

## When to Use

- You have multiple agent personas (markdown files) and want to pick which ones to use for a task
- You want to compose an ad-hoc team from different domains (e.g., Go review + database review + architecture)
- You want to browse what agents are available before deciding

## Where agents live

This workspace keeps its agents in `.claude/agents/*.md`, one flat directory, each
file opening with frontmatter:

```yaml
name: go-reviewer
description: Go code reviewer - ... /plan-prd dispatches it ... handing it a working directory and a base ref.
tools: Read, Grep, Glob, Bash
```

Global agents in `~/.claude/agents/*.md` are listed too; when a name exists in both,
the workspace's copy wins. Built-in agents (`Explore`, `Plan`, `general-purpose`) are
left out unless the user asks for them.

## How It Works

### Step 1: Discover Available Agents

Glob `.claude/agents/*.md` (and `~/.claude/agents/*.md`) and read each file's
frontmatter: `name` is the agent, the first sentence of `description` its summary,
`tools` whether it can write. Never hardcode the list — a new file appears in the
menu the next time this runs.

Group by what the agent does, read off its name and description:

- **Review** — `*-reviewer`, `code-reviewer`
- **Build** — `*-build-resolver`, `tdd-guide`
- **Design** — `planner`, `architect`, and anything else read-only that plans

An agent that fits none goes under **General**.

If no agents are found, say so and stop.

### Step 2: Present Domain Menu

```
Available agent domains:
1. Review — go-reviewer, typescript-reviewer, database-reviewer, ...
2. Build — go-build-resolver, tdd-guide, ...
3. Design — planner, architect

Pick domains or name specific agents (e.g., "1,3" or "go + database"):
```

- Skip domains with zero agents
- Show agent count per domain

### Step 3: Handle Selection

Accept flexible input:
- Numbers: "1,3" selects all agents from Review and Design
- Names: "go + database" fuzzy-matches against discovered agents
- "all from review" selects every agent in that domain

If more than 5 agents are selected, list them alphabetically and ask the user to narrow down: "You selected N agents (max 5). Pick which to keep, or say 'first 5' to use the first five alphabetically."

Confirm selection:
```
Selected: go-reviewer + database-reviewer
What should they work on? (describe the task):
```

### Step 4: Spawn Agents in Parallel

1. Read each selected agent's file — its `description` says what it must be handed
2. Prompt for the task description if not already provided
3. Work out the hand-off. Most agents here are layout-blind and **stop without a
   working directory**: a reviewer needs a working directory and a base ref, a build
   resolver or `tdd-guide` needs a working directory. Get each from the active task —
   `.claude/scripts/task.sh where <task> <repo>` for the directory, `task.sh report
   <task>` for the base. With no active task, offer only the read-only design agents,
   or ask which task to run against
4. Spawn all agents in parallel with the Agent tool, each under its own type:
   - `subagent_type: "<name>"` — the agent's own definition, tools and model apply
   - `prompt: "Task: {task description}\nWorking directory: {dir}\nBase ref: {base}"`,
     leaving out the lines that agent does not take
   - Each agent runs independently — no inter-agent communication needed
5. Do not select an agent that writes (`Write` or `Edit` in its `tools`) alongside
   another that works in the same directory — two writers in one checkout collide
6. If an agent fails (error, timeout, or empty output), note the failure inline (e.g., "go-reviewer: failed — [reason]") and continue with results from agents that succeeded

### Step 5: Synthesize Results

Collect all outputs and present a unified report:
- Results grouped by agent
- Synthesis section highlighting:
  - Agreements across agents
  - Conflicts or tensions between recommendations
  - Recommended next steps

If only 1 agent was selected, skip synthesis and present the output directly.

## Rules

- **Dynamic discovery only.** Never hardcode agent lists. New files in the directory auto-appear in the menu.
- **Max 5 agents per team.** More than 5 produces diminishing returns and excessive token usage. Enforce at selection time.
- **Parallel dispatch.** All agents run simultaneously — use the Agent tool's parallel invocation pattern.
- **Parallel Agent calls, not TeamCreate.** This skill uses parallel Agent tool calls for independent work. TeamCreate (a Claude Code tool for multi-agent dialogue) is only needed when agents must debate or respond to each other.

## Examples

```
User: team builder

Claude:
Available agent domains:
1. Review (6) — code-reviewer, database-reviewer, flutter-reviewer, go-reviewer, ...
2. Build (3) — dart-build-resolver, go-build-resolver, tdd-guide
3. Design (2) — architect, planner

Pick domains or name specific agents:

User: go + database

Claude:
Selected: go-reviewer + database-reviewer
What should they work on?

User: review the payment repo's change on the active task

[task.sh where <task> payment gives the working directory, task.sh report <task>
 the base; both agents spawn in parallel under their own types]

Claude:
## go-reviewer
- [findings...]

## database-reviewer
- [findings...]

## Synthesis
Both agents agree on: [...]
Tension: go-reviewer wants the lookup batched in the handler, database-reviewer wants an index instead. Resolution: [...]
Next steps: [...]
```