# release/

One set of deployment notes per release, written by `/deployment-notes` from a
stated list of branches, one line per service:

```
/deployment-notes <name>
<service> -> <feature> -> <target>      ->   release/<date>-<name>/
...                                            <date>-<name>.md     the notes
                                               <date>-<name>.html   the notes as a page, published as an artifact
                                               <service>-target/, <service>-feature/, diffs   the snapshot
```

A release is **not** a branch here. One wave can merge a feature branch into
several repos *and* hotfix branches straight into the same base on the same day,
while an app ships on a scheme of its own. Nothing can resolve that from a name,
so the branches are stated rather than inferred.

Every release fact in the notes comes from code, not from a pull request: a
hosted PR diff gives up past a size limit. Both branches of each service are
taken from origin - the SHA the server reports, never a local branch - and
exported side by side into `release/<date>-<name>/` -
`<service>-target/` and `<service>-feature/`, two directories per service - with
the merge-base diff and the exact SHAs beside them. A fetch that fails stops the
run rather than falling back to a stale ref, and
`deployment-notes.sh clean <name>` removes a snapshot's exports while keeping its
notes, page and artifact link.

A release usually ships while the app is still on TestFlight, so the notes check
every change for backward compatibility with the installed store builds, the
TestFlight build and the web at once.

What a repo's paths mean and how it ships are learned once per repo:
`/learn dev-deployment-note <repo>` for config, deploy, migrations
and rollback; `/learn qa-release-note <repo>` for who each path faces and where
its app routes links.

Each file has two sections for two readers:

- **Dev** - for whoever ships it: the verdict, impact, backward compatibility,
  the deploy steps in order (config, third parties, data, migrations, merges),
  rollback and what survives it, and what to check afterwards. The `dev-deployment-note`
  skill says how.
- **QA** - the release note: plain-language statements of what should be true
  after the release, grouped by feature, with no reference pointing outside
  itself, so it can be pasted to the QA team whole. The `qa-release-note` skill
  says how.

Notes written before 2026-10-06 sit loose in `release/` as `<date>-<name>.md`;
the oldest were written by `/release-notes`, the command's old name, with the QA
note first and the deploy material after it.

The notes and snapshots stay local — they describe private services — so this
README is the only tracked file here. The page `/deployment-notes` publishes is a
private artifact until you share its link.
