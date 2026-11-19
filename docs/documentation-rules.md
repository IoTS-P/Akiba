# Documentation rules

Applies to every repository in this project (the main repository, the framework,
the daemon, the frontend).

## Write the full URL when you link across repositories

The project is split into submodules. A path such as

```markdown
[Plan DSL](subprojects/akiba_framework/docs/plan-dsl.md)
```

resolves on disk, but the parent repository stores only a commit pointer for
`subprojects/akiba_framework`. On GitHub that path opens an empty page — the
link is broken even though the file exists.

Link the document where it actually lives:

```markdown
[Plan DSL](https://github.com/IoTS-P/Akiba-Framework/blob/master/docs/plan-dsl.md)
```

## Published documents describe use, not plans

These belong in the repository:

- what the software does and how to run it
- how to write a module or a plan
- configuration that a user has to know

These do not:

- migration and rollout plans
- internal refactor notes
- todo lists and design drafts

Keep them on disk and list them in `.gitignore`. If a page describes something
that has not shipped, it is a plan, not documentation.

## The README does not repeat what the repository page already shows

Releases, licenses and stars are visible on the repository home. A README
section that links to them adds a line to read and nothing to learn. Link only
documents that cannot be reached from the page itself.
