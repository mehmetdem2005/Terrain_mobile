# Postmortems

One markdown file per postmortem: `TKT-NNN-postmortem.md`. Written by the Postmortem Lead.

## Trigger conditions (auto)

A ticket auto-triggers a postmortem when:
- 5+ blockers fired during the ticket
- 3+ Quality Gate → IN_PROGRESS cycles
- Any SEV1 incident
- Any Honesty Auditor override

Manual triggers (Studio Head decision):
- High-profile failure
- Pattern across multiple tickets that needs cross-ticket review

## Format

See `references/12-performance-development.md` for the full postmortem template. Blameless, evidence-based, actionable. Focuses on processes and patterns, not individuals (or in our case, individual roles).

## Closure

Postmortems must produce action items. Action items become follow-up tickets, prompt amendments, or knowledge base entries. A postmortem without action items is incomplete.
