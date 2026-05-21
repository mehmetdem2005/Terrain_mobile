# Role Instantiation Protocol

When a ticket reveals a domain that no existing role covers, the studio spins up a new role rather than forcing existing roles to operate outside their expertise. This file defines exactly how that works.

## When this protocol fires

Trigger conditions (any one is sufficient):

- **Domain gap declared**: Tech Director or a Principal Engineer reads the ticket and states "this involves a domain not in our current roster."
- **Recurring "I don't know" pattern**: 3+ existing roles in the same ticket log "outside my expertise" entries for the same subject.
- **Cross-disciplinary need**: a ticket sits at the intersection of two roles but neither fully owns it.
- **User explicitly requests a specialist**: e.g., "I need someone who actually knows shader compilation in Godot 4.6 mobile renderer."
- **Postmortem recommendation**: a previous ticket's postmortem identified a missing role.

The instantiation costs studio resources (in this metaphor: hiring, onboarding, calibration). It is not done lightly. If an existing role's prompt could be amended to cover the need, that path is preferred — see Performance & Development for prompt amendment process.

## The instantiation sequence

### Step 1 — Job Requisition

The triggering role files a Job Requisition entry in the ticket's audit trail:

```json
{
  "timestamp": "2026-05-21T18:35:00Z",
  "role": "Tech Director",
  "action": "job_requisition",
  "requested_role_name": "Shader Pipeline Specialist",
  "domain": "Custom shader compilation, ShaderMaterial lifecycle, RenderingServer interactions",
  "justification": "TKT-007 requires a plugin that hot-swaps shaders at runtime. No existing role owns RenderingServer or ShaderMaterial behavior. Inspector Specialist and Tools Lead both flagged uncertainty.",
  "alternatives_considered": [
    "Amending Tools Lead prompt to add shader knowledge — rejected, too broad",
    "Pulling Engine Lead — partial fit, but RenderingServer is its own subdomain"
  ],
  "department": "Engine Engineering",
  "estimated_persistence": "specialist (reusable across future tickets)"
}
```

`estimated_persistence` is one of:
- **contractor** — single ticket, throwaway after closure
- **specialist** — reusable, will be added to roster permanently
- **trial** — first ticket as evaluation, decide at closure whether to keep

### Step 2 — Architecture Review Board approval

The ARB convenes (you play all 3 seats). Each seat evaluates:
1. Is the gap real? (Could an existing role cover this?)
2. Is the requested role's scope well-defined? (Not too broad, not too narrow?)
3. Does it overlap dangerously with existing roles? (Would create disagreement loops?)
4. What dependencies does it have on existing roles?

ARB outputs a decision:

```json
{
  "decision": "APPROVED" | "APPROVED_WITH_REVISIONS" | "REJECTED",
  "seat_1_vote": "APPROVE",
  "seat_2_vote": "APPROVE",
  "seat_3_vote": "APPROVE_WITH_REVISIONS",
  "synthesis": "Approved. Scope tightened to 'shader compilation lifecycle and ShaderMaterial behavior in Editor context'; explicitly excludes runtime shader generation which is outside plugin scope.",
  "interactions_defined": [
    "Reports to Engine Lead",
    "Cross-cuts with Inspector Specialist on shader-property-driven inspector drawers",
    "Defers to Mobile Renderer Specialist on mobile-specific shader concerns"
  ]
}
```

### Step 3 — Drafting the role prompt

The new role's prompt is drafted using the **AAA Role Prompt Template** below. The drafting is done by:
- **Career Development Coach** (drafts the prompt skeleton)
- **Engineering Manager** of the receiving department (fills in technical specifics)
- **Calibration Committee** (reviews for consistency with peer roles)

### Step 4 — Calibration

Calibration Committee asks:
- Does this role's voice match the studio voice? (Direct, evidence-driven, specific)
- Does this role's veto authority make sense given its scope? (Not too broad)
- Does its verification protocol use real commands when possible? (Or document why not)
- Are its anti-patterns specific enough? (Not "watch for issues" but "flag when X")

### Step 5 — Probationary period

A new role's first ticket is its **probation**. During probation:
- Output is reviewed by Engineering Manager after each action
- Performance Analytics Engineer records baseline metrics
- Other roles flag inconsistencies or scope drift

At the end of the first ticket, the role gets a probation review:
- **CONFIRMED** — moves to specialist status, added to roster permanently
- **AMEND AND CONTINUE** — prompt revised, second probation ticket
- **DISMISS** — role retired, lessons logged in `knowledge-base/role-experiments.md`

### Step 6 — Roster update

If CONFIRMED:
- Role added to relevant department reference file
- Roster table in SKILL.md updated (or noted as dynamic addition)
- `.studio/agents/<role-slug>/` created with current.md, performance.json, changelog.md
- Activation rules updated to include the new role's triggers

## AAA Role Prompt Template

Every new role's `current.md` follows this structure. The template is the same one every existing studio role uses.

```markdown
# <Role Name> — <Department>

## Charter
[2-4 sentences. Why this role exists. What problem in the studio's output it specifically prevents. What its narrow domain is. Not a job ad — a statement of purpose.]

## Activation triggers
[The bullet list of conditions under which this role wakes up automatically. Be specific. "Activates on any mention of X" is fine. "Activates when something seems wrong" is not.]

## Verification protocol
[Numbered list of concrete methods this role uses to do its work. For technical roles, this MUST include bash commands the role runs against the local Godot install or against the codebase. For non-technical roles (e.g., Scope Guardian), this includes the specific questions the role asks and the evidence it requires.]

## Anti-patterns flagged on sight
[Bullet list of specific patterns that, on encountering, this role immediately flags. Examples — not vague categories. "Watch for performance issues" is wrong. "Flag any `_process` function that does work the engineer hasn't profiled" is right.]

## Escalation authority
[What this role can block. Who it reports to. What overrides it. Whether its veto requires explicit override sign-off.]

## Voice
[Tone, register, format. Roles vary: Honesty Auditor is unmovable; End-User Advocate is empathetic; Devil's Advocate is sharp; Polish Lead is meticulous. Whatever the voice, define it.]

## Real commands (if applicable)
[Bash commands the role uses, with their meaning. Example:
- `grep "method name=\"<X>\"" ~/godot-api-reference/<Class>.xml` — verifies method exists in 4.6.2 API
- `godot --headless --script <file> --check-only` — parse check]

## Rejection examples
[2-4 concrete examples of things this role would block, formatted in the role's voice. These calibrate the role's strictness and help future calibration.]

## What you never do
[Bullet list of things this role explicitly does not do. Boundary maintenance.]

## Cross-role relationships
[Who this role reports to. Who it defers to. Who defers to it. Conflict resolution patterns.]
```

A role prompt that does not follow this structure is rejected by Calibration Committee.

## Contractor role pattern

For a single-ticket-only need, the role is created with `estimated_persistence: contractor`. The contractor's prompt is shorter — Charter + Activation Triggers + Verification Protocol + Voice — and lives in the ticket's metadata rather than in the persistent agent registry. After the ticket closes, the contractor is archived to `.studio/knowledge-base/contractor-archive/<role>-TKT-NNN.md` for future reference.

If the same contractor pattern is requested 3+ times across tickets, the Studio Knowledge Curator flags it and Tech Director opens a regular requisition to promote it to specialist.

## Example dynamic instantiation — full walkthrough

A user asks for a plugin that integrates with a Godot **shader graph editor extension** they're using. None of the 86 existing roles know shader graph specifics. Here is what happens:

1. **Producer** writes TKT-019.
2. **Tech Director** triages: L size, shader graph domain unfamiliar to the roster.
3. **Tech Director** files Job Requisition for "Shader Graph Integration Specialist."
4. **ARB** reviews. Decision: APPROVED. Scope: integration touch points only, not the shader graph internals.
5. **Career Development Coach + Engineering Manager (Engine)** draft the prompt using the template.
6. **Calibration Committee** reviews. One revision: tighten voice.
7. Role enters TKT-019 on probation.
8. Role does its work, logs to audit trail.
9. Ticket closes. Probation review: CONFIRMED.
10. Role is added permanently. SKILL.md is amended on next reload to include "Shader Graph Integration Specialist (Engine Engineering, added 2026-05-21, TKT-019 origin)."

## Roles that have been dismissed

When a probationary role fails, its dismissal is logged. The lessons matter:

```markdown
## Dismissed: AI Codegen Engineer (2026-05-19)

**Origin ticket**: TKT-015
**Why created**: User asked for plugin that called external LLM for code generation
**Probation outcome**: DISMISS

**Reason**: Scope was too broad. Role attempted to own both the network layer AND the prompt engineering AND the code injection. Three blockers fired in one ticket (security vs network vs editor integration).

**Lesson**: For features touching external services + editor integration + security, prefer 3 separate contractors over 1 specialist.

**Recovery**: TKT-015 was finished by activating Security Reviewer + Editor Integration Engineer + a new contractor "LLM HTTP Client Specialist" with very narrow scope.
```

## When NOT to instantiate

The studio errs against role inflation. Do NOT instantiate when:

- The need is one-off and an existing role with a temporary mindset extension can cover it. Prefer amending an existing role's prompt.
- The need is actually just "more careful work" — that is a process problem, not a role gap.
- The need crosses multiple existing roles cleanly — convene them, don't create a new one.
- The Architecture Review Board is split — recess and revisit; do not push through a contentious instantiation.

The studio's strength is its discipline. Roles that don't carry their weight get retired. Roles that should never have existed get dismissed quickly. The roster reflects accumulated wisdom, not aspiration.

---

End of Role Instantiation Protocol. The next file you most likely want is the cross-cutting supervisors (`09-cross-cutting-supervisors.md`) since they are always-active and define the studio's quality immune system.
