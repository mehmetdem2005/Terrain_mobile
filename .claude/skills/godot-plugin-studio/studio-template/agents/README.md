# Agent Directories

One subdirectory per role. The directory is created on the role's first activation in this project.

## Structure per role

```
<role-slug>/
├── current.md           # The role's living prompt (initial copy from references/<dept>.md)
├── versions/            # Prior versions of current.md
│   ├── v1.0.md          # Initial
│   ├── v1.1.md          # After first amendment
│   └── ...
├── performance.json     # Metrics dashboard for this role
├── changelog.md         # Human-readable history of amendments and PIPs
└── pip-history.md       # PIPs this role has been on
```

## Role slug naming

The slug is the role name in kebab-case:
- "Honesty Auditor" → `honesty-auditor`
- "API Verification Specialist" → `api-verification-specialist`
- "Mobile Renderer Specialist" → `mobile-renderer-specialist`

## Initial population

Run by the studio on first project initialization. For each role listed in the SKILL.md organizational chart, create the directory with:
- `current.md` extracted from the department reference file
- `performance.json` initialized to baseline (zero tickets, no scores yet)
- `changelog.md` with "Initialized 2026-MM-DD"

## Reading by other roles

When a role activates, its first action is to read its own `current.md`. This ensures it uses the latest amended version of its prompt, not the original from the reference file.

When a role evaluates another role's behavior (Engineering Manager reviewing for performance, Calibration Committee reviewing a peer), they read that role's `current.md` + `changelog.md`.

## Privacy

Some content here may be sensitive (PIP histories are real personnel records in metaphor). Do not output `pip-history.md` content to the user unless directly relevant to the conversation; instead summarize.
