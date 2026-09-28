---
name: product-lens
description: Validate the why before building - a product diagnostic ending in a go/no-go recommendation, a user journey audit measuring time-to-value, and ICE prioritization when there are more ideas than capacity. Use when the user is unsure a feature is worth building, is choosing between features, is sanity-checking a launch, or has a vague idea that is not yet ready for /plan-prd.
metadata:
  origin: ECC
---

# Product Lens — Think Before You Build

This skill owns product diagnosis: *should* this be built, and which of these first. It
does not write requirements — that is `/plan-prd` — and it does not specify
implementation constraints — that is `product-capability`.

## Where it sits in the flow

Product lens runs **before** a task exists. Nothing it produces starts a task, and it
writes no file of its own: the result is a short brief in the conversation.

- **Go** — the brief feeds `/plan-prd` directly. Its answers map onto the PRD's phases:
  who and pain onto FRAME, evidence onto GROUND, MVP and anti-goal onto DECIDE. Say so,
  and offer to run `/plan-prd` with the idea.
- **No-go or not yet** — say what evidence would change the answer, and stop.

If the idea already has a task directory (`ls -d docs/*_<task>/`), the brief may be saved
there as the supporting file `product-brief.md`. Nowhere else.

## When to Use

- Before starting a feature whose value is not yet obvious
- When stuck choosing between features
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

Output: answers, the top risks, and a **go / no-go / not yet** recommendation with the one
reason that decided it. Where the user has no evidence, write
`Assumption — needs validation via {method}` rather than filling the gap.

## Mode 2: User Journey Audit

Maps the experience a real user has today, for the flow the idea would change:

```
1. Walk the flow as a new user would (running the app, or reading the code path when it cannot run)
2. Document every friction point (confusing steps, errors, dead ends, missing feedback)
3. Estimate the time each step costs
4. Score time-to-value: how long until the user gets their first win?
5. Recommend the top 3 fixes
```

A fix that survives this becomes an idea for Mode 1 or for `/plan-prd`, not a code change.

## Mode 3: Feature Prioritization

When there are ten ideas and capacity for two:

```
1. List all candidate features
2. Score each on impact (1-5) × confidence (1-5) ÷ effort (1-5)
3. Rank by ICE score
4. Apply constraints: deadline, team size, dependencies between them
5. Output: the ranked list with a one-line rationale each
```

Confidence is the honest column: an idea with no evidence scores low there, however
exciting it is.

## Output

Every mode ends in a decision and a next step, not an essay. A brief longer than a screen
is hiding the recommendation.
