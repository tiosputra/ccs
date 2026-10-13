---
description: Decide go / no-go for every idea with the evidence from /brand and /market, rank the go ideas, and write business/decide.md
argument-hint: "[idea-name]   - no argument decides every idea"
allowed-tools: Bash(.claude/scripts/business.sh:*), Read, Write, Edit, Glob, Grep, Skill
---

## Result

!`.claude/scripts/business.sh slash decide`

## What this is

The last business pipeline, and the bridge to development. `/idea` gave each idea a
**gut** verdict; `/brand` and `/market` gathered evidence; this command re-judges every
idea **with that evidence** and ranks the survivors:

- `product-lens` **Mode 1 with evidence** — per idea: go, no-go, or not yet.
- `product-lens` **Mode 4** — ICE across the ideas that are not no-go.

It writes one file, `business/decide.md`: the current decision for the whole portfolio.
A `go` here is what `/plan-prd` starts from.

The result lists every idea with its gut verdict, what the brand and market pipelines
have written (`present` / `missing`), and, when `decide.md` exists, `newer` lines: inputs
written after the last decision, which that decision did not see.

An argument names one idea to focus on; the others keep their last verdict, carried
forward from `decide.md`, and are still ranked. The arguments were: `$ARGUMENTS`

## Your job

### 1. Check the evidence is there

| Facts | Then |
|---|---|
| `ideas none` | Stop. Nothing to decide - `/idea <name>` first |
| no `market_brief`, no `scan`, no `compete_report` | There is no evidence, so this would be the gut verdict again. Say so, recommend `/market scan`, and stop unless the user says to go ahead - then label every verdict `gut` |
| `scan` or `compete_report` present but no `market_brief` | Use them directly, and say `/market report` would tighten this |
| `positioning` is `-` | Go ahead; fit with the brand cannot be judged, which lowers confidence. Say so |
| `decide` present, no `newer` lines, no new idea | Nothing changed since the last decision. Show it and stop, unless the user asks to re-decide |

### 2. Read everything the result names

Each idea's `brief.md` (its answers, its riskiest assumption), the positioning file, the
market brief - or the scan and competitive report - and `project/`'s spec. Read the
existing `decide.md` too, if there is one: its verdicts are the baseline this run
changes, and every change gets a reason.

### 3. Judge each idea - Mode 1 with evidence

Load `product-lens`. For each idea, the seven questions again, but every answer now
**cites** a file: `market brief §3`, `compete/cards/forest.md`, `brandbook - positioning`.
The bar is the skill's: an assumption still unbacked counts **against** the idea.

The verdict for each idea is one of:

- **go** — ready for `/plan-prd`. The riskiest assumption held, or is cheap to test inside
  the first milestone.
- **not yet** — promising, but the evidence is missing. Say exactly which evidence and
  which command gets it.
- **no-go** — the evidence says no. Say what it would take to reopen it.

### 4. Rank - Mode 4

ICE over the go and not-yet ideas. Confidence comes from step 3: a not-yet idea cannot
score above 2 on it. No-go ideas are listed, not ranked.

### 5. Write `business/decide.md`

```markdown
# Go / no-go

- **Decided:** <today>
- **Inputs:** <each file read, with the date business.sh printed for it>

## Verdicts

| Idea | Gut | Now | The reason | Evidence | What would change it |
|---|---|---|---|---|---|

## Priorities (ICE)

| Rank | Idea | Impact | Confidence | Effort | ICE | Why |
|---|---|---|---|---|---|---|

## <idea-name>

<one section per idea: the seven answers with their citations, the verdict, the risks>

## Next step

<one line: usually `/plan-prd <the top idea> from branch <ref>`>

## Previous decisions

- <date> — <idea>: <verdict> (<one-line reason>)
```

On a re-run, move the old verdict table's rows into **Previous decisions** as one line
each, then write the new decision above. The history is how a reversal stays visible -
never drop it.

Do not change any idea's `brief.md`. The brief records the gut call as it was made;
`decide.md` is where the evidence lives.

### 6. Report

```
DECIDED: business/decide.md
  go       <idea> (rank 1, ICE n), …
  not yet  <idea> - needs <evidence> via <command>
  no-go    <idea> - <reason>
Changed since last time: <idea: was -> now>, or "first decision"

Next: /plan-prd <top idea> from branch <ref>
```

`/plan-prd` needs a source branch and never guesses one, so leave `<ref>` for the user.

## Refuse

- **Never start a task or run `/plan-prd` yourself.** A go is a recommendation; the user
  types `/plan-prd`, and its Gate 1 is where development is approved.
- **Never write outside `business/decide.md`.**
- **Never upgrade a verdict without new evidence.** Re-running with nothing new produces
  the same decision.
