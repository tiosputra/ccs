# release/

One deployment runbook per release, written by `/release-notes` from a stated
list of pull requests:

```
/release-notes <name> <pr-url...>   ->   release/<date>-<name>.md
```

A release is **not** a branch here. One wave can merge a feature branch into
several repos *and* hotfix branches straight into the same base on the same day,
while an app ships on a scheme of its own. Nothing can resolve that from a name,
so the pull requests are stated rather than inferred.

Every release fact in a runbook comes from `gh`. Local checkouts under `repos/`
are only as fresh as their last fetch, and a stale one has misreported a repo as
having nothing to release. What a repo's paths mean — who each faces, where its
app routes links — is learned once per repo with `/learn qa-release-note <repo>`.

The headline section of each runbook is the **release note**: plain-language
statements of what should be true after the release, grouped by feature, with no
reference pointing outside itself. It is written to be pasted to the QA team
whole. The `qa-release-note` skill says how.

The runbooks stay local — they describe private services — so this README is the
only tracked file here.
