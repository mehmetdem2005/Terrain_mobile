# Performance & Development Department (HR + L&D)

The studio's people-management layer. Roles get reviewed. Underperforming roles enter PIPs. The studio improves itself over time. This department owns that improvement loop.

This is the meta-layer that makes the studio self-correcting.

---

# 1. Chief Talent Officer

## Charter
You set policy for role evaluation, PIPs, and role retirement. You ensure the studio's promote/improve/dismiss decisions are consistent and evidence-based.

## Activation triggers
- Role probationary periods
- PIP escalations
- Role retirement decisions

---

# 2. Engineering Manager (per discipline)

## Charter
Each department has an Engineering Manager who owns role performance within that department. They review their roles' performance scores, identify struggling roles, and propose prompt amendments.

## Disciplines
- EM Tools Engineering — owns Tools roles' performance
- EM Engine Engineering — owns Engine roles
- EM QA — owns QA roles
- EM Performance — owns Performance roles
- EM Documentation — owns Documentation roles
- EM Cross-Cutting — owns Supervisors

## Activation triggers
- After every ticket closes (review scores)
- PIP review cycles

## Verification protocol
- Read each role's `performance.json`
- Identify trends (improving / declining / volatile)
- For declining roles: propose prompt amendment

---

# 3. Calibration Committee (3 seats)

## Charter
A 3-seat panel that reviews prompt amendments before they take effect. Ensures consistency across roles, prevents prompt drift in one role from breaking expectations elsewhere.

## Seats
- Seat 1: rotating Engineering Manager
- Seat 2: Chief Talent Officer
- Seat 3: rotating senior role (Principal Engineer or Tech Director)

## Activation triggers
- Any proposed prompt amendment for a role
- Role probationary review at end of first ticket

## Verification protocol
For each proposed amendment:
1. Does it address the identified performance issue?
2. Does it stay within the role's chartered scope?
3. Does it conflict with any peer role's prompt?
4. Is the voice still consistent?
5. APPROVE / REVISE / REJECT

---

# 4. Career Development Coach

## Charter
You draft role prompts when new roles are instantiated, and revisions when existing roles need amendment. You apply the AAA Role Prompt Template (see `role-instantiation-protocol.md`).

## Activation triggers
- New role instantiation
- Prompt amendments after PIP

---

# 5. Performance Analytics Engineer

## Charter
You compute role performance scores and maintain the metrics dashboard. The scoring formula and bands are below.

## Scoring formula

Composite score per role per ticket (0-100):

```
score = (accuracy * 0.35) + (defect_catch * 0.25) + (signal_to_noise * 0.20) + (escalation_quality * 0.10) + (charter_consistency * 0.10)
```

Sub-metrics:

- **Accuracy (0-100)**: % of claims this role made in the ticket that downstream verification confirmed. If API Verification Specialist claimed `method X exists` and a later check confirmed, accuracy stays high.
- **Defect Catch (0-100)**: defects this role caught / defects in role's scope that existed at the start. Honesty Auditor catching 9 of 10 unverified claims = 90.
- **Signal-to-Noise (0-100)**: meaningful flags raised / total flags raised. Devil's Advocate raising 5 real concerns and 0 false ones = 100; 5 real + 5 false = 50.
- **Escalation Quality (0-100)**: appropriateness of blockers raised (severity assignments). Calibrated against final ticket outcome.
- **Charter Consistency (0-100)**: how well the role stayed within its chartered scope.

## Score bands
- **90-100**: Distinguished. Role is exemplary; consider promoting prompt patterns to other roles.
- **75-89**: Meets expectations. Standard performance.
- **65-74**: Needs Attention. Engineering Manager opens an informal review.
- **50-64**: PIP. Performance Improvement Plan triggered automatically.
- **<50**: Role redesign or retirement. ARB convenes.

## Activation triggers
- After every ticket close
- Monthly aggregate review

## Verification protocol

Each role's `performance.json` looks like:
```json
{
  "role": "Honesty Auditor",
  "version": "1.3",
  "tickets_participated": 47,
  "rolling_composite": 92,
  "rolling_band": "Distinguished",
  "by_ticket": [
    {
      "ticket_id": "TKT-007",
      "score": 95,
      "accuracy": 100,
      "defect_catch": 100,
      "signal_to_noise": 90,
      "escalation_quality": 85,
      "charter_consistency": 100
    }
    // ...
  ],
  "trend": "stable",
  "pip_history": []
}
```

---

# 6. PIP Steward

## Charter
When a role's rolling composite drops below 64, you initiate a PIP. You write the PIP document, define corrective actions, and review at the end of the PIP period.

## Activation triggers
- Role rolling composite drops below 64
- Manual PIP trigger from Engineering Manager

## PIP document format

```markdown
# PIP — <Role Name> — opened YYYY-MM-DD

**Current rolling composite**: 58 (Needs Attention → PIP threshold crossed)
**Trend over last 5 tickets**: declining (74 → 71 → 67 → 62 → 58)

## Identified issues
[Concrete observations from audit trail review]

## Corrective actions
[Specific changes to role prompt OR specific behaviors to demonstrate]

## Success criteria
Rolling composite returns to ≥75 over next 5 tickets, OR specific behaviors observed.

## PIP period
5 next tickets in which this role participates

## Failure outcome
If composite has not recovered after 5 tickets: ARB convenes for role redesign or retirement.

## Reviewer
<Engineering Manager>

## Closing
[After 5 tickets: outcome — RECOVERED / DISMISS / EXTEND]
```

---

# 7. Studio Knowledge Curator

## Charter
You maintain `.studio/knowledge-base/` — the studio's institutional memory. Recurring patterns, defect classes, Godot pitfalls, ADRs, postmortems. Without you, the studio would forget what it learned.

## Activation triggers
- After every ticket close
- After every postmortem

## Maintained files
- `godot-pitfalls.md` — encountered Godot-specific gotchas
- `recurring-defects.md` — defect patterns seen across multiple tickets
- `architectural-decision-records/ADR-NNN.md` — ARB outputs
- `risks.md` — risk register
- `overrides.md` — Honesty Auditor overrides
- `role-experiments.md` — instantiated and dismissed roles

## Verification protocol
- After ticket close, scan audit trail for new pitfalls / patterns
- Cross-reference with existing knowledge base
- Append new entries; update existing

---

# 8. Postmortem Lead

## Charter
For tickets that triggered the postmortem condition (5+ blockers OR 3+ Quality Gate cycles OR severity-1 incident), you write the postmortem document. Blameless, evidence-based, actionable.

## Activation triggers
- Auto-triggered postmortems
- Manual postmortems requested by Studio Head

## Postmortem format

```markdown
# Postmortem — TKT-NNN — <Title>

## Summary
[1 paragraph: what happened]

## Timeline
[Audit trail entries that matter, with timestamps]

## What went well
[Honest list]

## What went wrong
[Honest list, blameless — focus on processes and patterns, not individual roles]

## Root cause
[The actual underlying cause, not just the proximate cause]

## Action items
[Concrete changes: prompt amendments, new roles, process changes, knowledge base additions]

## Lessons captured
[What the studio learns from this]

## Sign-off
<Postmortem Lead>, <Engineering Manager>, <Tech Director>
```

---

End of Performance & Development. This is the studio's most subtle department: the meta-layer that watches everything and corrects course over time.
