# `.che/plans/` — local work plans

Drop a markdown file per plan into this directory. `che status` reads each
`*.md` file and shows it in a **plans** section with a colored status badge.

The file format is plain markdown with optional YAML frontmatter. Plans
without frontmatter are still listed (without a badge), so the simplest
plan is just a `.md` file with notes inside.

## Frontmatter fields

```yaml
---
name: short display name (defaults to the filename)
status: open | in-progress | done | blocked
progress: free-form, e.g. "60%" or "3/5 steps"
---
```

Only `status` drives the badge color:

| status        | badge     |
|---------------|-----------|
| `done`        | green     |
| `in-progress` | yellow    |
| `blocked`     | red       |
| `open` or unset | dim     |

## Example

`.che/plans/auth-rewrite.md`:

```markdown
---
name: Rewrite auth middleware
status: in-progress
progress: 3/5 steps
---

Replace the legacy session middleware with token-based auth.

- [x] Inventory call sites
- [x] Draft new middleware
- [x] Wire feature flag
- [ ] Migration script
- [ ] Roll out and remove old code
```

`che status` will render this as:

```
plans
  in-progress  Rewrite auth middleware (3/5 steps) (auth-rewrite.md)
```

## Notes

- `README.md` in this directory is ignored by `che status`.
- The list is unsorted — name your files so alphabetical order makes sense
  (e.g. prefix with a number or date if you want a specific order).
- Plans are local to the repo and meant for *active work*. Long-term
  archival belongs in commit messages or external tools.
