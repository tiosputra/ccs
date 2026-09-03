# release/

One deployment runbook per release, written by `/release-notes` from a stated
list of pull requests:

```
/release-notes <name> <pr-url...>   ->   release/<date>-<name>.md
```

A release is **not** a branch here. The 5.1 wave merged `feature/m5.1` in five
repos *and* merged `hot/…` and `5.1-additional/…` straight to `main` on the same
day, while `mobile` used a scheme of its own. Nothing can resolve that from a
name, so the pull requests are stated rather than inferred.

Every fact in a runbook comes from `gh`. The checkouts under `repos/` cannot be
refreshed from a session and have been stale enough to mislead — on 2026-09-02
they reported one service as having nothing to release and another as a 22-file
change against a real 51.

The headline section of each runbook is the **release note**: plain-language
statements of what should be true after the release, grouped by feature, with no
reference pointing outside itself. It is written to be pasted to the QA team
whole.
