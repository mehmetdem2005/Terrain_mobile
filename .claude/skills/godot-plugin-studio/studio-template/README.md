# Studio Template — Copy to `.studio/` in Your Project

This directory is the template for the studio's persistent memory. On first activation of the skill in a project, the studio copies this template to `.studio/` in your working directory. From then on, `.studio/` holds:

- **`agents/`** — One subdirectory per role. Each contains `current.md` (the role's living prompt), `versions/` (prior versions of the prompt), `performance.json` (the role's metrics), and `changelog.md` (amendments and PIP history).
- **`tickets/`** — One JSON file per ticket. Audit trails live here. Closed tickets are not deleted.
- **`postmortems/`** — Postmortem documents for tickets that triggered them.
- **`knowledge-base/`** — The studio's institutional memory:
  - `godot-pitfalls.md` — encountered Godot-specific gotchas
  - `recurring-defects.md` — defect patterns
  - `architectural-decision-records/` — ADRs
  - `risks.md` — risk register
  - `overrides.md` — Honesty Auditor overrides
  - `role-experiments.md` — instantiated/dismissed roles
- **`studio-config.json`** — Thresholds, scoring weights, customizations.

## Why the persistence exists

Without `.studio/`, the studio resets every conversation. Persistence makes the studio actually improve over time — accumulated ADRs, recurring-defect knowledge, role performance history. After 10-20 tickets, a properly maintained `.studio/` directory is more valuable than the SKILL.md itself, because it represents the lessons the studio has learned about *your specific project*.

## Initialization

On first run in a project, the studio:
1. Checks if `.studio/` exists
2. If not, copies this template's contents to `.studio/`
3. Initializes role agent directories from the department reference files
4. Writes initial `studio-config.json`
5. Notes "Studio initialized" in audit trail

## Backup

`.studio/` should be checked into version control. Treat it as source of truth for the studio's state in this project.

## Editing manually

You can edit `.studio/` files directly. Especially useful:
- Adjusting role prompts (effectively, customizing the studio for your project)
- Editing `studio-config.json` thresholds (e.g., raising the PIP threshold if you find the default too strict)
- Adding entries to `knowledge-base/godot-pitfalls.md` from outside the ticket flow
