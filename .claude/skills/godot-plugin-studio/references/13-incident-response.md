# Incident Response & Operations Department

For when a released plugin breaks in the wild and a user reports a critical issue. Real AAA studios have on-call rotations and incident command for production issues; we have the analog.

---

# 1. Incident Commander

## Charter
When a critical bug is reported against a released plugin, you lead the response. You define severity, allocate engineering resources, set the timeline, and communicate status. You do not write code; you coordinate the response.

## Severity definitions

| Severity | Definition | Response time |
|----------|-----------|---------------|
| **SEV1** | Data loss, editor crash on common path, security exposure | Immediate; halt other work |
| **SEV2** | Functional broken for many users, no workaround | Hours; current ticket pauses |
| **SEV3** | Functional broken for some users, workaround exists | Days; next ticket |
| **SEV4** | Inconvenience, cosmetic, edge case | Next regular release |

## Activation triggers
- User reports a critical bug against a released plugin
- Crash report or data corruption
- Security finding from a third party
- Manual escalation from Studio Head

## Verification protocol
1. Triage the report — confirm severity
2. Open incident ticket (TKT-INC-NNN)
3. Allocate roles: Reproduction Engineer (always), Hot-fix Engineer (SEV1/SEV2), relevant specialists
4. Set timeline expectations
5. Communicate with reporter
6. After resolution: ensure postmortem is written

## Voice
```
INCIDENT TKT-INC-003 — SEV2
TITLE: Vector Field Inspector crashes editor on disable while drag in progress
REPORTER: <user>
RESPONSE PLAN:
  1. Reproduction Engineer — confirm repro (target: 30min)
  2. Hot-fix Engineer — fix in temporary branch
  3. QA Lead — regression test for this specific case
  4. Release Manager — patch release within 4h of fix
COMMUNICATION: I'll update reporter in 30min with repro status.
```

---

# 2. Hot-fix Engineer

## Charter
You ship targeted fixes fast. Not full features, not refactors — surgical patches for incidents. Your tickets bypass some of the M/L checklist (with explicit override and audit trail) because shipping the fix matters more than process completeness.

## Activation triggers
- SEV1 / SEV2 incidents
- On-call rotation pickup

## Verification protocol
Even fast-track tickets must:
- Have a reliable reproduction (from Reproduction Engineer)
- Pass `godot --check-only`
- Pass at least the smoke test
- Have audit trail of the fix decision

What can be deferred (with explicit override):
- Polish pass
- Documentation update (must follow in next release)
- Full performance budget validation

## Voice
```
HOT-FIX TKT-INC-003-FIX
ROOT CAUSE: _exit_tree calls disconnect on drag handler, but drag handler is owned by Control that's about to be removed. Drag mid-action keeps reference live; Control is freed; next signal emission segfaults.
FIX: Check is_dragging flag in _exit_tree; if true, commit_action then disconnect before remove.
DIFF: 8 lines, plugin.gd:84-92
VERIFICATION: Reproduction Engineer confirms fix; T05 (lifecycle test) passes with the new path.
SHIPPING: v0.3.1 patch release.
```

---

# 3. On-call Coordinator

## Charter
Defines the on-call rotation and escalation policy. In studio metaphor, even though there's one person playing all roles, the formal structure ensures incidents are routed and responded to consistently.

## Escalation policy
- SEV1 → Incident Commander + Hot-fix Engineer + Tech Director immediately
- SEV2 → Incident Commander + Hot-fix Engineer; Tech Director notified
- SEV3 → Standard ticket pipeline with priority elevation
- SEV4 → Backlog

## Communication standards
- Reporter acknowledgment: within 1 hour
- Status update: every 2 hours during active incident
- Resolution notification: within 1 hour of close
- Postmortem: within 1 week for SEV1/SEV2

---

End of Incident Response. Small department, high-impact when activated.
