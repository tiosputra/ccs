---
name: ops-release-note
description: Use when writing or reviewing the Operations section of deployment notes, or any release note for the operations team - turning a stated set of changes into what the people who run the business day to day will see differently - new or changed admin panel screens, Google Sheets the system now reads or writes (new tabs, columns, sync changes), WhatsApp messages and alerts, emails, push notifications, chat alerts, and scheduled jobs - and what they must do before, during and after the release. Also read by /deployment-notes, which hands it the `ops` and `surface` records.
metadata:
  origin: workspace
---

# Ops Release Note

The third reader of a release. Dev asks *what must be done to ship it*; QA asks
*what should be true afterwards*; operations asks **what changes in my day** -
the screens I work in, the sheets I keep, the messages I receive or that
customers now get, and anything I must do so it keeps working.

This file is the method. Who a path faces comes from the repo's learned
`qa-release-note` surfaces; where a repo keeps its message templates or sheet
code is read from the diff. Start with each repo's `AGENTS.md` where it has one.

## Where the facts come from

| Record | Gives | Judge it by |
|---|---|---|
| `ops` sheet | code that reads or writes a spreadsheet | a new sheet, tab or column; a changed order or format; sync timing; what happens when the sheet is wrong |
| `ops` whatsapp / email / push / chat | code that sends a message | who receives it, what triggers it, when, and whether it is new, changed or removed |
| `ops` schedule | a job on a timer | what it does, when it runs in the team's local time, what they see when it fails |
| `surface` facing staff or admin | a changed admin or internal path | a new screen, menu, button, filter, approval or export someone uses |

The script over-reports on purpose: a variable named `emailError` is not an
email. **Read the code** behind every record before writing a line, and drop
what nobody in operations could notice. A message only a developer receives
(a log, an error tracker) belongs in Dev, not here.

## What each entry holds

Plain language, no file paths, no code - an operator reads this, not an
engineer. Name screens by the menu path they click, messages by what they say
and when they arrive, sheets by their name and tab. Each entry says:

- **What** - the screen, sheet, message or job, in their words.
- **Was / now** - for a change to something they already use. A new thing says
  `New`. A removed thing says so, and what replaces it.
- **Who** - who uses the screen, who receives the message (customer, venue,
  internal team), who owns the sheet.
- **When** - the trigger, and the time in the team's timezone for anything
  scheduled.
- **If it goes wrong** - the alert they would get, what it means, and who to
  tell. A failure alert is itself an entry: "if the booking sheet sync fails,
  the ops WhatsApp group receives *…* - tell the on-call developer".
- **Action** - anything they must do: insert a column before the deploy, fill
  a new tab, change a procedure, brief customer service on a new message. Say
  *before*, *at* or *after* the release.

Mark what the code did not settle - a recipient read from config, a template
whose wording lives outside the repo - as **to confirm**, and add it to the
notes' open questions. Never guess who receives a message.

## Shape

Numbered under the section the command gives it (`3.1`, `3.2`, ...), each
heading starting with its number so it shows in the page's contents, one
subsection per kind, in this order, each omitted only with a line saying
`No changes`:

1. **At a glance** - the three or four things operations will notice first,
   and every action they must take, with when.
2. **Admin panel** - new and changed screens, grouped by menu.
3. **Google Sheets** - per sheet: tabs and columns added, moved or renamed,
   what now writes to it, how often. Column changes that must happen before
   the deploy are called out first; a sync that writes by column position
   breaks silently when a column is missing.
4. **WhatsApp** - customer-facing messages, then internal alerts.
5. **Email** - the same split.
6. **Push and other alerts** - app notifications, chat channels.
7. **Scheduled jobs** - what now runs on its own, and when.
8. **What operations must do** - one checklist collected from the entries
   above, ordered before / at / after the release. Each item points back to its
   entry by number; the fact lives once, in the entry.

## Writing it

- Self-contained, like the QA note: it can be pasted to the operations team
  whole, so it points at nothing outside itself.
- Never write a phone number, an email address, a sheet ID, a template ID or a
  customer's data. Name the group, inbox or sheet instead.
- A message's wording may be quoted when it is fixed text in the code; a
  message assembled from customer data is described, never quoted with values.
