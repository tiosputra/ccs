---
name: product-lens
description: Validate the why before building - a product diagnostic ending in a go / no-go / not-yet verdict, a founder review of product-market-fit signals, a user journey audit measuring time-to-value, and ICE prioritization when there are more ideas than capacity. Use when writing or revising an idea brief or a go/no-go decision, when the user is unsure a feature is worth building, is choosing between ideas, is sanity-checking a launch, or has a vague idea not yet ready for /plan-prd.
metadata:
  origin: ECC
---

# Product Lens — Think Before You Build

This skill owns product diagnosis: *should* this be built, and which of these first. It
does not write requirements — that is `/plan-prd` — and it does not specify
implementation constraints — that is `product-capability`.

## Where it sits in the flow

Product lens runs **before** a task exists, and nothing it produces starts one. Two
commands hand it a destination; anywhere else, the result is a short brief in the
conversation and no file.

| Caller | Mode | Evidence |
|---|---|---|
| `/idea` | Mode 1, **gut** | What the founder said. Every unbacked answer is an assumption |
| `/decide` | Mode 1 **with evidence**, then Mode 4 | The idea's brief, the brand, the market brief |

A **go** feeds `/plan-prd`: who and pain map onto its FRAME phase, evidence onto GROUND,
MVP and anti-goal onto DECIDE. Say so and offer the hand-off. A **no-go** or **not yet**
says what evidence would change the answer, and stops.

## When to Use

- Before starting a feature whose value is not yet obvious
- When stuck choosing between ideas
- Before a launch — sanity check the user journey
- When converting a vague idea into something `/plan-prd` can take

## Mode 1: Product Diagnostic

Asks the hard questions, in one set:

```
1. Who is this for? (specific person or role, not "users")
2. What's the pain? (quantify: how often, how bad, what do they do today?)
3. Why now? (what changed that makes this possible or necessary?)
4. What's the 10-star version? (if time were unlimited)
5. What's the MVP? (smallest thing that proves the thesis)
6. What's the anti-goal? (what are you explicitly NOT building?)
7. How do you know it's working? (a metric, not vibes)
```

Output: the answers, the top risks, and a verdict line with the one reason that decided it:

```
- **Verdict:** go | no-go | not yet — <the one reason>
```

That line is read by machinery, so keep it on one line and spelled exactly so.

**Gut** and **with evidence** are the same questions with a different bar:

- **Gut** — answer from what the founder said. Where there is no evidence, write
  `Assumption — needs validation via {method}` rather than filling the gap. A gut verdict
  may be `go`, but it is a go to *investigate*, and says which assumption matters most.
- **With evidence** — every answer cites its source (the market brief, a competitor
  card, the brandbook). An assumption still unbacked at this stage counts against the
  verdict; it is not neutral. A `go` here means ready for `/plan-prd`.

## Mode 2: Founder Review

Reviews the whole project through a founder's eyes — run it when the question is "are we
building the right thing at all", not about one idea:

```
1. Read the project's own statement of itself: its spec, README, recent work
2. Infer what it is trying to be, in one sentence
3. Score product-market-fit signals 0-10, each with the evidence behind it:
   usage trajectory, retention, revenue, moat (what is hard to copy?)
4. Name the one thing that would 10x it
5. Flag work in flight that does not matter
```

## Mode 3: User Journey Audit

Maps the experience a real user has today, for the flow an idea would change:

```
1. Walk the flow as a new user would (running the app, or reading the code path when it cannot run)
2. Document every friction point (confusing steps, errors, dead ends, missing feedback)
3. Estimate the time each step costs
4. Score time-to-value: how long until the user gets their first win?
5. Recommend the top 3 fixes
```

A fix that survives this becomes an idea for Mode 1 or for `/plan-prd`, not a code change.
`browser-qa` can verify a web journey's findings.

## Mode 4: Feature Prioritization

When there are ten ideas and capacity for two:

```
1. List all candidate ideas
2. Score each on impact (1-5) × confidence (1-5) ÷ effort (1-5)
3. Rank by ICE score
4. Apply constraints: deadline, team size, dependencies between them
5. Output: the ranked list with a one-line rationale each
```

Confidence is the honest column: an idea with no evidence scores low there, however
exciting it is. An idea whose Mode 1 verdict is `no-go` is listed but not ranked.

## Output

Every mode ends in a decision and a next step, not an essay. A brief longer than a screen
is hiding the recommendation.
