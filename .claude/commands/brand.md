---
description: Build the brand under business/branding/ - the discovery interview, the voice profile, and where each stands
argument-hint: "[status] | discover | voice"
allowed-tools: Bash(.claude/scripts/business.sh:*), Read, Write, Edit, Glob, Grep, Skill, WebFetch
---

## Result

!`.claude/scripts/business.sh slash brand $1`

## What this is

The brand pipeline. It writes one thing, the brand, into `business/branding/`, and it is
project-wide: there is one brand, not one per idea.

```
business/branding/
├── state.json          brand-discovery's checkpoint - which module is done, which is next
├── modules/            one file per interview module, 10_purpose-why.md … 90_SYNTHESIS.md
│   └── 90_SYNTHESIS.md the brandbook: the module everything downstream reads
├── founders/           one file per founder, only when more than one is interviewed
└── voice.md            brand-voice's VOICE PROFILE, measured from real writing
```

Downstream readers: `/market compete` takes its client positioning brief from the
brandbook (or `20_positioning.md` before the brandbook exists); `/decide` weighs each idea
against it; `/idea --investor-material` writes in `voice.md`'s voice.

The result's first line is the mode. Then `module` rows - `done`, `in-progress`,
`written` (a module file the checkpoint does not count yet), or `pending` - and the
voice profile's state. The module list is read from the `brand-discovery` skill's
reference files, so it always matches the skill.

## mode: brand-status

Show where the brand stands, as a short table: each module and its status, then the
voice profile. Then suggest **one** next step, from the facts:

| Facts | Next step |
|---|---|
| `state` missing | `/brand discover` - start at module 10 |
| a module `in-progress`, or `next_module` set | `/brand discover` - continue at that module |
| a module `written` but not `done` | the checkpoint is behind the files; offer to reconcile `state.json` from the module files |
| `state` `invalid` | the checkpoint is unreadable; show it, offer to rebuild it from the module files - never discard module files |
| every module `done`, `voice` missing | `/brand voice`, if real writing exists to measure |
| all done | `/market compete` - positioning is ready to be benchmarked |

## mode: brand-discover

Load the `brand-discovery` skill and run its session-start protocol, handing it
`business/branding/` (absolute: the workspace root plus that path) as the brand-identity
directory. Do not ask where to save.

- Module files go in `business/branding/modules/`, founders' answers in
  `business/branding/founders/`, the checkpoint at `business/branding/state.json`.
- The interview is the skill's: one question at a time, laddering, saturation before
  synthesis. Follow it; do not compress it into a questionnaire to finish faster. A module
  that takes three sessions takes three sessions.
- Write each module file and update `state.json` when the module closes - never only at
  the end of the conversation. A session can end at any point.
- If the founder gives you existing material (a pitch, a manifesto, `project/`'s spec),
  read it to sharpen the questions; it does not replace the answers.

When the session stops, report the module, its status, and what comes next, so
`/brand` with no argument picks up the same thread.

## mode: brand-voice

Load the `brand-voice` skill. Its source material is **real writing by the founder or the
brand** - ask for samples, links or paths; use only what the user names. `project/` and
any published store or site copy count as the lowest-priority source.

- Write the VOICE PROFILE to `business/branding/voice.md`, with a line saying which
  sources it was measured from and today's date. Revise that file in place on a re-run.
- If `modules/50_voice-tone.md` exists, compare: that module is the intended voice, this
  profile is the measured one. List where they disagree; do not reconcile them silently.

## mode: brand-unknown

The argument was not a subcommand. Say the three that exist - `status` (or nothing),
`discover`, `voice` - and stop.

## Refuse

- **Never write outside `business/branding/`.** The brand is not the project's spec, and a
  design token file is code - that is `design-system`, inside a task.
- **Never delete or overwrite a module file to make `state.json` agree.** Module files
  are the record; the checkpoint is derived from them.
- **Never invent an answer for the founder.** A module with no answer stays open.
