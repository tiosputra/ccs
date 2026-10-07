---
name: council
description: Convene a four-voice council for ambiguous decisions, tradeoffs, and go/no-go calls. Use when multiple valid paths exist and you need structured disagreement before choosing.
metadata:
  origin: ECC
---

# Council

Convene four advisors for ambiguous decisions:
- the in-context Claude voice
- a Skeptic subagent
- a Pragmatist subagent
- a Critic subagent

This is for **decision-making under ambiguity**, not code review, implementation planning, or architecture design.

## When to Use

Use council when:
- a decision has multiple credible paths and no obvious winner
- you need explicit tradeoff surfacing
- the user asks for second opinions, dissent, or multiple perspectives
- conversational anchoring is a real risk
- a go / no-go call would benefit from adversarial challenge

Examples:
- monorepo vs polyrepo
- ship now vs hold for polish
- feature flag vs full rollout
- simplify scope vs keep strategic breadth

## When NOT to Use

| Instead of council | Use |
| --- | --- |
| Verifying whether output is correct | `santa-method` |
| Breaking a feature into implementation steps | `/plan` (or the `planner` agent for an independent draft) |
| Designing system architecture | `architect` |
| Reviewing code for bugs or security | `/plan-prd`'s review step, or `/code-review` |
| Straight factual questions | just answer directly |
| Obvious execution tasks | just do the task |

## Where this sits in the flow

A council is called by the user, at one of the two points where a decision is still
open:

- **Before Gate 1**, when the PRD has a real fork - two credible approaches and no
  clear winner. The verdict goes into the PRD before you confirm it.
- **At Gate 2**, for a ship-or-hold call on finished work.

Between the gates, the confirmed PRD and plan are the decision; a council there
relitigates what Gate 1 already settled. If a build turns up a genuinely new fork,
stop and raise it with the user rather than convening a council on your own.

## Roles

| Voice | Lens |
| --- | --- |
| Architect | correctness, maintainability, long-term implications |
| Skeptic | premise challenge, simplification, assumption breaking |
| Pragmatist | shipping speed, user impact, operational reality |
| Critic | edge cases, downside risk, failure modes |

The three external voices should be launched as fresh subagents with **only the question and relevant context**, not the full ongoing conversation. That is the anti-anchoring mechanism.

## Workflow

### 1. Extract the real question

Reduce the decision to one explicit prompt:
- what are we deciding?
- what constraints matter?
- what counts as success?

If the question is vague, ask one clarifying question before convening the council.

### 2. Gather only the necessary context

If the decision is codebase-specific:
- collect the relevant files, snippets, issue text, or metrics
- keep it compact
- include only the context needed to make the decision

If the decision is strategic/general:
- skip repo snippets unless they materially change the answer

### 3. Form the Architect position first

Before reading other voices, write down:
- your initial position
- the three strongest reasons for it
- the main risk in your preferred path

Do this first so the synthesis does not simply mirror the external voices.

### 4. Launch three independent voices in parallel

Each subagent gets:
- the decision question
- compact context if needed
- a strict role
- no unnecessary conversation history

Prompt shape:

```text
You are the [ROLE] on a four-voice decision council.

Question:
[decision question]

Context:
[only the relevant snippets or constraints]

Respond with:
1. Position — 1-2 sentences
2. Reasoning — 3 concise bullets
3. Risk — biggest risk in your recommendation
4. Surprise — one thing the other voices may miss

Be direct. No hedging. Keep it under 300 words.
```

Role emphasis:
- Skeptic: challenge framing, question assumptions, propose the simplest credible alternative
- Pragmatist: optimize for speed, simplicity, and real-world execution
- Critic: surface downside risk, edge cases, and reasons the plan could fail

### 5. Synthesize with bias guardrails

You are both a participant and the synthesizer, so use these rules:
- do not dismiss an external view without explaining why
- if an external voice changed your recommendation, say so explicitly
- always include the strongest dissent, even if you reject it
- if two voices align against your initial position, treat that as a real signal
- keep the raw positions visible before the verdict

### 6. Present a compact verdict

Use this output shape:

```markdown
## Council: [short decision title]

**Architect:** [1-2 sentence position]
[1 line on why]

**Skeptic:** [1-2 sentence position]
[1 line on why]

**Pragmatist:** [1-2 sentence position]
[1 line on why]

**Critic:** [1-2 sentence position]
[1 line on why]

### Verdict
- **Consensus:** [where they align]
- **Strongest dissent:** [most important disagreement]
- **Premise check:** [did the Skeptic challenge the question itself?]
- **Recommendation:** [the synthesized path]
```

Keep it scannable on a phone screen.

## Persistence Rule

Nothing is written by default, and never to a shadow path such as `~/.claude/notes`.
When the council changes something real:

- **Inside a task** - the verdict goes where the task keeps its decisions: the PRD's
  approach (before Gate 1), an ADR through `architecture-decision-records` when it sets
  lasting policy, and a **Decided** entry through `/save-session`.
- **A lesson that outlives the task** - a fact about a service or a cross-task rule -
  goes to the memory graph through `knowledge-ops`.

## Multi-Round Follow-up

Default is one round.

If the user wants another round:
- keep the new question focused
- include the previous verdict only if it is necessary
- keep the Skeptic as clean as possible to preserve anti-anchoring value

## Anti-Patterns

- using council for code review
- using council when the task is just implementation work
- feeding the subagents the entire conversation transcript
- hiding disagreement in the final verdict
- persisting every decision as a note regardless of importance

## Related Skills

- `santa-method` — adversarial verification
- `knowledge-ops` — persist a lesson that outlives the task in the memory graph
- `search-first` — gather external reference material before the council if needed
- `architecture-decision-records` — formalize the outcome when the decision becomes long-lived system policy

## Example

Question:

```text
Should payment v3 replace v2 for every merchant at once, or roll out behind a per-merchant flag?
```

Likely council shape:
- Architect pushes against carrying two payment paths longer than necessary
- Skeptic questions whether per-merchant control is actually needed
- Pragmatist asks what can ship this week without risking settlement
- Critic focuses on mixed-state merchants, reconciliation, and rollback

The value is not unanimity. The value is making the disagreement legible before choosing.