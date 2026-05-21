# Studio Knowledge Base

The studio's institutional memory. Grows over time as tickets close and lessons accumulate. Maintained by the **Studio Knowledge Curator** role.

## Files

| File | Purpose | Maintained by |
|------|---------|---------------|
| `godot-pitfalls.md` | Specific Godot 4.6.2 gotchas encountered in real tickets | Studio Knowledge Curator + API Verification Specialist |
| `recurring-defects.md` | Defect patterns seen across multiple tickets | Studio Knowledge Curator + Postmortem Lead |
| `architectural-decision-records/` | ADRs from ARB outputs | Architecture Decision Recorder |
| `risks.md` | Open risk register | Risk Officer |
| `overrides.md` | Honesty Auditor overrides (permanent record) | Studio Head + Audit Trail Officer |
| `role-experiments.md` | Instantiated and dismissed roles | Chief Talent Officer |

## How knowledge grows

After every ticket closes:
1. Studio Knowledge Curator scans audit trail for novel pitfalls / patterns
2. Cross-references with existing entries
3. Appends new entries; updates existing if related
4. Maintains a date stamp per entry so trends are visible

After every postmortem:
1. Postmortem Lead extracts lessons
2. Adds to `recurring-defects.md` if the defect pattern crossed >1 ticket
3. May open a follow-up ticket to address systemic issue

## Why this matters more than the SKILL.md after 20 tickets

The SKILL.md is generic — the studio's charter applied to any Godot project. The knowledge base is *yours* — your project's accumulated lessons, your team's recurring defect classes, your architectural decisions. After enough tickets, this is the studio's most valuable artifact.

## Editing policy

Add freely. Removing entries should be deliberate — even old pitfalls inform future tickets. If a pitfall is no longer relevant (e.g., a Godot 4.6 bug fixed in 4.7), mark it as `SUPERSEDED` rather than delete.

## Format conventions

Each entry has:
- A short title
- Date encountered
- Ticket ID(s) where it appeared
- Description
- Mitigation / lesson
- Status (ACTIVE / SUPERSEDED / RESOLVED)
