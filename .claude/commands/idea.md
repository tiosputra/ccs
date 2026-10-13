---
description: Shape a business idea into a gut-level brief (product-lens Mode 1) under business/ideas/<idea>/, optionally with investor material
argument-hint: "<idea-name> [--investor-material]   - then describe the idea on the lines below"
allowed-tools: Bash(.claude/scripts/business.sh:*), Read, Write, Edit, Glob, Grep, Skill
---

## Result

!`.claude/scripts/business.sh slash idea`

## What this is

The first of the business pipelines. A **task** changes code in repos and runs through
`/plan-prd`'s two gates; an **idea** changes nothing in a repo. It is a founder's hunch
written down well enough to be judged:

```
/idea      business/ideas/<idea>/brief.md      gut verdict - this command
/brand     business/branding/                  who we are and how we sound
/market    business/marketing/                 the evidence
/decide    business/decide.md                  go / no-go with evidence, ranked
   go  ->  /plan-prd                           the idea becomes a task
```

The result above lists the ideas that already exist, with the verdict each brief
records, and `today`. It was run without your arguments on purpose: the description
is free text, and free text is never handed to a shell.

## Your job

### 1. Read the invocation

The arguments were:

```
$ARGUMENTS
```

- The **first word** is the idea name. `--investor-material` anywhere asks for investor
  material. Everything else is the founder's description of the idea.
- No name, or no description: ask for the missing one and stop.
- Run `.claude/scripts/business.sh idea <name>`. It checks the name and prints the idea's
  directory and what is in it.
  - `valid no` — propose a kebab-case name (2–4 words) and ask before going on.
  - `exists yes` — read the existing `brief.md`. This run **revises** it in place: say so,
    keep its `Written` date, set `Revised` to `today`. Never write `brief-v2.md` or a second
    directory for the same idea.
  - The name is fixed once written. It is the handle `/decide` and `/plan-prd` use later.

### 2. Ground it, lightly

This is the **gut** pass: no web research, no market sizing - that is `/market`'s job,
and doing it here would make `/market` repeat it. Read only what is already on disk:

- `project/` — what the project is already building, so the brief says where this idea
  fits beside it (an extension, a pivot, a separate product).
- The brandbook's positioning, if `/brand` has written one (`business.sh brand` prints
  what exists).
- Other ideas' briefs only if this one overlaps them; say which.

### 3. Run the diagnostic

Load the `product-lens` skill and run **Mode 1, gut**. The founder's description usually
answers some of the seven questions already; restate those, and ask the rest **in one
set**. Accept "skip" — the answer becomes `Assumption — needs validation via {method}`.
Do not ask a second round unless an answer contradicts another.

### 4. Write the brief

Write `business/ideas/<idea>/brief.md`, creating the directory:

```markdown
# <Idea, as a title>

- **Idea:** <idea-name>
- **Written:** <today> · **Revised:** —
- **Stage:** gut
- **Verdict:** go | no-go | not yet — <the one reason that decided it>

## The idea

<the founder's description, tightened to 2–4 sentences>

## Diagnostic

| # | Question | Answer | Basis |
|---|---|---|---|
| 1 | Who is this for? | … | founder · or `Assumption — needs validation via {method}` |
| … | … | … | … |

## Fit with the project

<extension / pivot / separate product, and what it would compete with inside the project>

## Top risks

1. …

## Riskiest assumption

<the single assumption that would kill the idea if wrong, and the cheapest way to test it -
usually a question for `/market scan`>

## Next step

<one line>
```

The `**Verdict:**` line is read by `business.sh` — keep it on one line, spelled exactly so.

### 5. Investor material — only with `--investor-material`

Load `investor-materials`. Write into `business/ideas/<idea>/investor/`:

| File | What |
|---|---|
| `facts.md` | The source of truth, written **first**: problem, customer, market, model, traction, team, ask, use of funds — each a value or `Assumption — …`. Every other file reads its numbers from here |
| `one-pager.md` | The one-pager / memo |
| `deck-outline.md` | The 12-slide flow, one section per slide, speaker line and the fact each slide rests on |

Never invent traction, revenue, a raise size or team credentials the founder did not
state: those stay assumptions in `facts.md` and are flagged on the slide that needs
them. If `business/marketing/brief.md` exists, cite its market numbers instead of
estimating; if `business/branding/voice.md` exists, write in that voice.

A rendered HTML deck is a separate ask. Offer it; on a yes, load `frontend-slides` and
write `deck.html` in the same directory.

### 6. Report

```
IDEA: <idea-name> - business/ideas/<idea>/brief.md   (new | revised)
Verdict (gut): <go | no-go | not yet> - <reason>
Riskiest assumption: <one line>
Investor material: <files written | not requested>

Next: <one of>
  /market scan          the riskiest assumption is a market question
  /brand discover       nothing says who this is for or how it is positioned yet
  /decide               evidence already exists for it
```

## Refuse

- **Never start a task.** `/idea` does not run `task.sh`, does not create a branch, and
  does not write under `tasks/` or `repos/`. An idea becomes a task only through
  `/plan-prd`, after `/decide` or the user says go.
- **Never write outside `business/ideas/<idea>/`.** Not `project/` — an idea is not the
  project's spec until a task changes it.
- **Never send anything outward.** Investor material stays on disk; sharing it is the
  user's act.
