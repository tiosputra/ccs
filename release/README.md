# release/

One set of deployment notes per release, written by `/deployment-notes` from a
stated list of pull requests:

```
/deployment-notes <name> <pr-url...>   ->   release/<date>-<name>.md
```

A release is **not** a branch here. One wave can merge a feature branch into
several repos *and* hotfix branches straight into the same base on the same day,
while an app ships on a scheme of its own. Nothing can resolve that from a name,
so the pull requests are stated rather than inferred.

Every release fact in the notes comes from `gh`. Local checkouts under `repos/`
are only as fresh as their last fetch, and a stale one has misreported a repo as
having nothing to release. What a repo's paths mean and how it ships are learned
once per repo: `/learn dev-deployment-note <repo>` for config, deploy, migrations
and rollback; `/learn qa-release-note <repo>` for who each path faces and where
its app routes links.

Each file has two sections for two readers:

- **Dev** - for whoever ships it: the verdict, impact, breaking changes, what to
  prepare (config, secrets, third parties, migrations), the deploy order, rollback
  and what survives it, and what to check afterwards. The `dev-deployment-note`
  skill says how.
- **QA** - the release note: plain-language statements of what should be true
  after the release, grouped by feature, with no reference pointing outside
  itself, so it can be pasted to the QA team whole. The `qa-release-note` skill
  says how.

Files from before 2026-10-06 were written by `/release-notes`, the command's old
name, with the QA note first and the deploy material after it.

The notes stay local — they describe private services — so this README is the
only tracked file here.
