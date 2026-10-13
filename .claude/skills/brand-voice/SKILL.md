---
name: brand-voice
description: Build a source-derived writing style profile from real posts, essays, launch notes, docs, or site copy, then reuse that profile across content, outreach, and social workflows. Use when the user wants voice consistency without generic AI writing tropes.
metadata:
  origin: ECC
---

# Brand Voice

Build a durable voice profile from real source material, then use that profile everywhere instead of re-deriving style from scratch or defaulting to generic AI copy.

## Where it sits in the flow

`/brand voice` runs it and hands it the file to keep the profile in. Writing anywhere
else - investor material, a market brief, launch copy - loads the saved profile rather
than re-deriving one. When a brandbook exists, its voice-and-tone module says what the
voice *should* be; this skill measures what it *is* in real writing, and says where
the two disagree instead of silently picking one.

## When to Activate

- the user wants content or outreach in a specific voice
- writing for X, LinkedIn, email, launch posts, threads, or product updates
- adapting a known author's tone across channels
- the existing content lane needs a reusable style system instead of one-off mimicry

## Source Priority

Use the strongest real source set available, in this order:

1. recent original social posts and threads
2. articles, essays, memos, launch notes, or newsletters
3. real outbound emails or DMs that worked
4. product docs, store listings, changelogs, README framing, and site copy

Do not use generic platform exemplars as source material.

## Collection Workflow

1. Gather 5 to 20 representative samples when available.
2. Prefer recent material over old material unless the user says the older writing is more canonical.
3. Separate "public launch voice" from "private working voice" if the source set clearly splits.
4. Ask the user for samples, links or paths; never fetch an account or page they did not name.
5. If site or store copy matters, include the live version, not a draft.

## What to Extract

- rhythm and sentence length
- compression vs explanation
- capitalization norms
- parenthetical use
- question frequency and purpose
- how sharply claims are made
- how often numbers, mechanisms, or receipts show up
- how transitions work
- what the author never does

## Output Contract

Produce a reusable `VOICE PROFILE` block that downstream skills can consume directly. Use the schema in [references/voice-profile-schema.md](references/voice-profile-schema.md).

Keep the profile structured and short enough to reuse in session context. The point is not literary criticism. The point is operational reuse.

## When sources are thin

Say so and build a provisional profile from what exists, marked provisional. Do not
borrow another brand's defaults to fill the gap.

## Hard Bans

Delete and rewrite any of these:

- fake curiosity hooks
- "not X, just Y"
- "no fluff"
- forced lowercase
- LinkedIn thought-leader cadence
- bait questions
- "Excited to share"
- generic founder-journey filler
- corny parentheticals

## Persistence Rules

- Reuse the latest confirmed `VOICE PROFILE` across related tasks in the same session.
- Save the profile where the caller hands it - `/brand voice` hands one - and nowhere else.
- Do not create repo-tracked files that store personal voice fingerprints unless the user explicitly asks for that.

## Downstream Use

Load the saved profile before writing:

- launch posts, store listings, release notes meant for users
- investor material (`investor-materials`), so the deck sounds like the founder
- cold or warm outreach

If another skill already has a partial voice capture section, this skill is the canonical source of truth.
