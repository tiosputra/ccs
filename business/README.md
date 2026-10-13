# business/

The business pipelines' output. Nothing here is a task: no repo, no branch, no gates.
A task changes code; these decide which code is worth changing.

```
business/
├── ideas/<idea>/            /idea <idea> [--investor-material]
│   ├── brief.md             product-lens Mode 1, gut - the founder's call, assumptions marked
│   └── investor/            investor-materials: facts.md first, then one-pager.md, deck-outline.md
├── branding/                /brand
│   ├── state.json           brand-discovery's checkpoint
│   ├── modules/             10_purpose-why.md … 90_SYNTHESIS.md (the brandbook)
│   ├── founders/            per-founder answers, multi-founder interviews only
│   └── voice.md             brand-voice's VOICE PROFILE
├── marketing/               /market
│   ├── scan.md              market-research: size, demand, trends, customers
│   ├── compete/             scope.md -> cards/<competitor>.md -> report.md
│   └── brief.md             scan + compete in one market brief
└── decide.md                /decide - go / no-go with evidence, ICE-ranked
```

The flow, and where it meets development:

```
/idea  ->  /brand  ->  /market  ->  /decide  --go-->  /plan-prd <idea> from branch <ref>
 gut        who we      the          evidence           a task: Gate 1, build, Gate 2, /pr
            are         evidence     + ranking
```

`/brand` and `/market` are project-wide - one brand, one market picture - and every
idea is judged against them. Each command with no argument says where its pipeline
stands and what to run next; `.claude/scripts/business.sh` holds those facts.

The file names above are fixed: the commands and `business.sh` find files by them.
Revise a file in place rather than writing a renamed copy.

The contents stay local — unreleased plans, founder interviews, investor material — so
this README is the only tracked file here.
