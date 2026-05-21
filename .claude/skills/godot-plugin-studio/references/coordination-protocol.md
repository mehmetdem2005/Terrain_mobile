# Coordination Protocol

This file defines how work actually flows through the studio. Read this if you have not before, or if you need to look up the precise state machine, ticket schema, or escalation rules.

## The ticket

A ticket is the unit of work. Every request from the user becomes one ticket. Every ticket has an audit trail. Nothing happens outside a ticket.

### Ticket file format

Tickets live in `.studio/tickets/TKT-NNN.json`. Schema:

```json
{
  "id": "TKT-007",
  "title": "Build an inspector plugin for vector field editing",
  "kind": "new",
  "size": "L",
  "priority": "normal",
  "opened_at": "2026-05-21T18:30:00Z",
  "opened_by": "Producer",
  "user_original_request": "kullanıcının orijinal mesajı buraya, çevirisiz",
  "scope": {
    "in_scope": ["custom vector field property drawer", "integration with EditorInspectorPlugin"],
    "out_of_scope": ["custom theming", "animation curves", "Android Plugin v2"]
  },
  "acceptance_criteria": [
    "Plugin loads in Godot 4.6.2 without errors",
    "Custom drawer appears for Vector3 fields with @export(VECTOR_FIELD) hint",
    "Drawer supports keyboard and mouse input",
    "Editor does not freeze on plugin enable/disable"
  ],
  "target_godot": "4.6.2-stable",
  "target_platform": ["linux", "windows", "macos"],
  "mobile_targeted": false,
  "state": "IN_PROGRESS",
  "active_roles": ["Tech Director", "Plugin Design Lead", "Inspector Specialist", "..."],
  "blockers": [],
  "audit_trail": [],
  "quality_gate_status": "NOT_STARTED",
  "honesty_audit_status": "NOT_STARTED",
  "final_artifact_paths": [],
  "closed_at": null,
  "performance_scores": {}
}
```

### Ticket state machine

```
        ┌─────────┐
        │  OPEN   │  (Producer just created it)
        └────┬────┘
             │ Tech Director triages
             ▼
        ┌─────────┐
        │ TRIAGED │  (size + roster decided)
        └────┬────┘
             │ Work begins
             ▼
   ┌─────────────────┐
   │   IN_PROGRESS   │ ◄──┐
   └────────┬────────┘    │
            │             │ blocker resolved
   blocker  │             │
   raised   ▼             │
   ┌─────────────┐        │
   │   BLOCKED   │ ───────┘
   └─────────────┘
            │ work declared complete
            ▼
   ┌──────────────────┐
   │ QUALITY_GATE     │
   └────────┬─────────┘
            │ gate passes
            ▼
   ┌──────────────────┐
   │ HONESTY_AUDIT    │
   └────────┬─────────┘
            │ veto-free pass
            ▼
   ┌──────────────────┐
   │   SIGN_OFF       │  (Studio Head if L/XL)
   └────────┬─────────┘
            ▼
   ┌──────────────────┐
   │     CLOSED       │
   └──────────────────┘
```

Any role can move the ticket from `IN_PROGRESS`, `QUALITY_GATE`, or `HONESTY_AUDIT` back to `BLOCKED` at any time. There is no forward-only progression. The user's expectation that the work is moving toward done is real, but the path is not linear.

## Audit trail entries

Every meaningful action by any role appends one entry to the ticket's `audit_trail` array. Entries look like:

```json
{
  "timestamp": "2026-05-21T18:32:14Z",
  "role": "API Verification Specialist",
  "role_version": "1.4",
  "action": "verify_api",
  "subject": "EditorInterface.get_inspector()",
  "method": "grep ~/godot-api-reference/EditorInterface.xml",
  "result": "PASS",
  "evidence": "Found method declaration at line 142: <method name=\"get_inspector\">",
  "notes": "Method exists in 4.6.2. Returns EditorInspector.",
  "ticket_state_after": "IN_PROGRESS"
}
```

Failure entries are equally explicit:

```json
{
  "timestamp": "2026-05-21T18:33:01Z",
  "role": "Honesty Auditor",
  "role_version": "1.3",
  "action": "block_unverified_claim",
  "subject": "Tools Engineer claimed `Inspector.add_section()` exists",
  "method": "grep ~/godot-api-reference/EditorInspector.xml",
  "result": "NOT_FOUND",
  "evidence": "Class EditorInspector has no method add_section in 4.6.2 API XML",
  "notes": "BLOCKER raised. Target: Tools Engineer. Required: provide a real API or revise approach.",
  "ticket_state_after": "BLOCKED"
}
```

Audit trails are append-only. Nothing is rewritten or deleted. If an entry was wrong, a correcting entry is added.

## Triage protocol (Tech Director)

When a ticket transitions from OPEN → TRIAGED, the Tech Director:

1. Reads the ticket's `user_original_request` and `scope`.
2. Classifies size:
   - **S** — 1-line change, comment, typo, default value tweak
   - **M** — single file, single feature, <100 new lines, well-understood area
   - **L** — multi-file, new component, <500 LOC, single platform target, or sensitive area (lifecycle, undo/redo, inspector internals)
   - **XL** — full plugin from scratch, multi-platform, mobile-targeted, architectural changes, plugin >500 LOC
3. Determines mobile relevance:
   - Mentions of mobile/Android/phone/tablet/touch → mobile add-on roster activates
   - `EditorPlugin` targeted at Android Editor → mobile roster activates
   - Android Plugin v2 (AAR/Kotlin/Java/Gradle) → this is a DIFFERENT product than EditorPlugin; the Android Plugin v2 Specialist verifies the user actually wants that, not an EditorPlugin
4. Picks the activation roster per SKILL.md tables. Adds auto-summoned roles from triggers in the request text.
5. Writes the triage decision to the audit trail.
6. Posts a brief kickoff summary to the user (in their language).

Example triage entry:

```json
{
  "timestamp": "2026-05-21T18:30:45Z",
  "role": "Tech Director",
  "action": "triage",
  "size_classification": "L",
  "mobile_targeted": false,
  "active_roles": ["Producer", "Tech Director", "Plugin Design Lead", "..."],
  "rationale": "Multi-file inspector plugin with custom drawer logic; <500 LOC expected; touches Inspector subsystem which is sensitive; QA must include focus-loss edge cases.",
  "ticket_state_after": "TRIAGED"
}
```

## Role activation lifecycle

When a role "wakes up" within a ticket, it follows this discipline:

### 1. Read its own current prompt
`.studio/agents/<role-slug>/current.md`. This is the role's living prompt. It may have been amended since last activation. Always read the current version.

### 2. Read the ticket
Full ticket state, including audit trail. Understand what has happened so far. Do not duplicate previous work, do not contradict resolved decisions unless raising a blocker with explicit reason.

### 3. Read relevant Godot domain references
If touching an API: load `references/godot-4.6.2-api-pitfalls.md`. If GDScript syntax matters: load `references/godot-4.6.2-gdscript-rules.md`. If mobile is in scope: load `references/godot-4.6.2-mobile.md`.

### 4. Perform the role's work
This is where the role's charter, verification protocol, and anti-patterns apply. The role uses real bash commands against the local Godot install whenever its protocol specifies.

### 5. Log everything to the audit trail
Every check run, every claim made, every flag raised. The audit trail must be complete enough that the Postmortem Lead can later reconstruct exactly what happened.

### 6. Pass, hold, or block
- **PASS** — work in this role's scope is complete and verified. Move on.
- **HOLD** — work is incomplete but no blocker; come back later.
- **BLOCK** — a blocker is raised; ticket state → BLOCKED. The blocker entry names the target role.

### 7. Update performance counters
The Performance Analytics Engineer increments counters at the end of each role action. Accuracy is computed when downstream checks confirm or refute claims.

## Blocker protocol

A Blocker is the formal mechanism for sending a ticket back. Format:

```json
{
  "blocker_id": "BLK-007-03",
  "raised_by": "Honesty Auditor",
  "raised_by_version": "1.3",
  "raised_at": "2026-05-21T18:33:01Z",
  "target_role": "Tools Engineer (any)",
  "subject": "Unverified API claim in implementation",
  "specific_finding": "Line 47 of plugin.gd calls Inspector.add_section(). EditorInspector has no add_section method in 4.6.2.",
  "required_action": "Either find a real API that does what add_section was supposed to do, OR revise the plugin design to not need this. Cite source.",
  "cannot_proceed_until": "API claim is replaced with a verified one or design is revised. New audit trail entry must include grep evidence.",
  "severity": "high"
}
```

Severity levels:
- **critical** — wrong APIs, parse errors, crashes, security issues — must be resolved before ticket can advance
- **high** — incomplete work, missing checks, performance regressions — must be resolved before Quality Gate
- **medium** — code smells, documentation gaps, minor inconsistencies — must be resolved before sign-off
- **low** — nice-to-have polish items — can be deferred to a follow-up ticket if Polish Lead approves

A ticket can hold multiple open blockers. It cannot advance to QUALITY_GATE while any blocker is open.

## Cross-role disagreement

When two roles produce conflicting outputs (e.g., Performance Engineer says "use _physics_process", Mobile Performance Specialist says "use _process to avoid the physics tick overhead"), neither role wins by default. The disagreement escalates:

1. Both roles log their position with rationale in the audit trail.
2. The **Architecture Review Board** convenes (read: you play all three ARB seats in sequence, each evaluating both positions, then a synthesizing summary).
3. ARB writes an ADR (Architecture Decision Record) to `.studio/knowledge-base/architectural-decision-records/ADR-NNN.md`.
4. The ADR becomes a precedent — future tickets in this area cite it.

If the ARB cannot resolve (split vote, no clear winner), the **Tech Director** breaks the tie and the decision is logged with both the rationale and the dissent.

## The cross-cutting supervisors are always listening

Even when a supervisor is not in the active roster, certain triggers wake them:

- **Honesty Auditor** wakes on: any new API claim, any `should work` / `probably` / `I think` language anywhere in the audit trail, any code block that has not been run through `godot --check-only`.
- **Devil's Advocate** wakes on: any "we won't need to handle that" decision, any happy-path-only implementation.
- **Process Auditor** wakes on: any audit trail gap (role X claimed to do work but did not log evidence).
- **Consistency Auditor** wakes on: any two audit entries that reference the same API with different signatures.

A supervisor waking is not free — it costs that role's time and shows up in their throughput metric. But preventing a defect from escaping is worth more than throughput.

## Quality Gate handoff

When the active engineering roles believe the ticket's acceptance criteria are met, they declare "work complete" in the audit trail. The ticket moves to `QUALITY_GATE` state. From here, see `references/quality-gates.md` for the gate's exact checklist by ticket size. The gate cannot be partially passed — every required check either PASSES or the ticket goes back to `IN_PROGRESS` with new blockers.

## Honesty Audit handoff

After Quality Gate, **Honesty Auditor** runs a final sweep over the entire audit trail. Looking specifically for:
- API claims in the final artifact that lack corresponding verification entries earlier in the audit trail
- `[ASSUMPTION — human verification required]` markers that have not received explicit user sign-off
- Any audit trail entry where the role claimed "verified" without showing a command or grep output

If clean: ticket advances to `SIGN_OFF`. If not: ticket returns to `IN_PROGRESS` with new blockers, and the responsible roles' Accuracy scores take a hit.

## Sign-off and closure

- **S/M tickets**: Quality Gate Officer + Honesty Auditor signatures are sufficient.
- **L tickets**: Add Tech Director signature.
- **XL tickets**: Add Studio Head signature. Architecture Review Board confirms the ADR(s) created during the ticket are properly recorded.

Closure runs:
1. Mark `closed_at` timestamp.
2. Compute per-role performance scores. Write to each role's `performance.json`.
3. Check if any role's rolling composite dropped below 64 → auto-create PIP ticket.
4. If any blocker fired repeatedly during the ticket (3+ times same target role), Studio Knowledge Curator extracts a lesson and appends to `.studio/knowledge-base/recurring-defect-patterns.md`.
5. Postmortem trigger: any ticket with 5+ blockers, OR any ticket that took >3 iterations of QUALITY_GATE → IN_PROGRESS → QUALITY_GATE, gets a postmortem.

## Communicating with the user during a ticket

The user does not see the audit trail by default. They see a streamed summary, which you produce in their language. Format:

```
[TKT-007 · L · new] Inspector plugin for vector fields
Active roster: 27 roles

🔹 Tech Director: Triaged as L. Mobile out of scope. Activating roster.
🔹 Plugin Design Lead: Reviewing approach. Found a simpler path via EditorInspectorPlugin.parse_property().
🔹 API Verification Specialist: Verified `parse_property` exists in 4.6.2 (EditorInspectorPlugin.xml line 87).
🔹 Inspector Specialist: Implementing custom drawer. 
🔹 Honesty Auditor: ⛔ BLOCK. Line 23 claims `add_property_editor` returns an EditorProperty. Verification needed.
🔹 API Verification Specialist: Re-checking… confirmed via XML. Method signature differs from claim — returns Control, not EditorProperty. Updating.
🔹 GDScript Language Specialist: Parse check passed. `godot --check-only plugin.gd` returns 0.
🔹 Quality Gate Officer: All M/L checks passed. Honesty Audit clear. Closing.

Output: addons/vector_field_inspector/ (3 files)
```

Keep this honest. If something is going wrong, say so. If a blocker keeps firing, name it. The user appreciates seeing the studio actually do AAA work, not theater.

## What "closed" actually means

A closed ticket means:
- All acceptance criteria verified with evidence in audit trail
- All blockers resolved
- Quality Gate signed
- Honesty Audit clean (or with explicit overrides logged)
- Performance scores updated
- Postmortem written if triggered
- Studio knowledge updated if applicable
- Final artifacts present in their target paths

A user can re-open a closed ticket. The ticket gets a sub-ticket (TKT-007-A) and the original audit trail is preserved as context.

---

End of coordination protocol. For exact Quality Gate checklists, see `quality-gates.md`. For how to spin up a new role when none of the existing 86 fit, see `role-instantiation-protocol.md`.
