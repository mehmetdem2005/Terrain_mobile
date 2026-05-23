# Risk Register Protocol (v2.2)

The studio's protocol for **identifying, tracking, and reconciling risks** before they become incidents. This is what pre-production discipline looks like in an AAA studio: you don't enter execution without knowing what could blow up.

In v2.1, Phase 1.B (Discovery) did "risk thinking" implicitly. Engineers and the Tech Director would notice concerns, mention them in discussion, sometimes log them in the audit trail. But there was no **artifact**, no **owner per risk**, no **reconciliation at close**. Risks evaporated as fast as they appeared, and tickets executed without the studio formally acknowledging what was being bet on.

This protocol fixes that. Every L/XL ticket produces a `risk-register.md` at Phase 1.B close. At Phase 1.G, the register is reopened and reconciled: which risks materialized, which were ducked, which surfaced new ones.

---

## What's a risk in this context?

A risk is **something specific that could cause this ticket to fail, ship broken, or create downstream damage**, with non-trivial probability. Risks are not:

- Generic worries ("bugs might happen")
- Aesthetic concerns ("the code might be ugly")
- Things already controlled by other protocols ("we might violate the manifesto" — Architecture Veto handles that)
- Hypothetical 1-in-1000 events ("a meteor might hit the data center")

Risks ARE:

- Concrete, articulable threats
- Tied to this ticket's specific scope
- Plausible enough that a senior engineer would lose sleep over them
- Actionable — either mitigatable, monitorable, or worth accepting consciously

The test: **can you write a one-sentence "what could go wrong"?** If yes, it's a risk. If you can't, it's a vague feeling and doesn't go in the register.

---

## When the register is produced

**Phase 1.B close.** After Discovery, before Architecture (Phase 1.C). The flow is:

1. Discovery activities (codebase understanding, dependency mapping, prior art research, knowledge consult)
2. **Risk identification session** (new step)
3. Phase 1.B exit gate
4. → Phase 1.C begins with the register in hand

Phase 1.C (Architecture) consumes the register — alternatives are evaluated partly on how they handle each known risk.

---

## Format

Strict format. Free-form risks don't get tracked, same problem as free-form lessons.

```markdown
# Risk Register — TKT-NNN

## R1: <One-sentence risk title>
**Probability**: [low | medium | high]
**Impact**: [low | medium | high | critical]
**Category**: [api-stability | data-loss | performance | platform-compat | security | scope-creep | dependency | architectural | other]
**Source**: <how the risk was identified — e.g., "Knowledge Loop L-014 cited it in TKT-023", "Discovery surfaced uncertain Godot behavior", "Mobile target makes this likely", "Designer concern raised in intake">
**Description**: <2-4 sentences. What specifically could go wrong, under what conditions, with what consequence.>
**Mitigation**: <What this ticket's plan will do to reduce probability or impact. If "accept and monitor," say so explicitly.>
**Owner**: <Role name. The role responsible for the mitigation actually happening.>
**Trigger to escalate**: <What signal would tell us this risk is materializing in real time. Could be "a specific test fails", "compile error of type X", "behavior Y observed", or "(none — risk only visible at close)".>

## R2: ...
```

### Probability and impact levels

| Probability | Meaning |
|-------------|---------|
| low | <20% — possible but unlikely; we plan for the normal case |
| medium | 20-60% — coin-flip range; we explicitly plan for this happening |
| high | >60% — likely; mitigation is mandatory, not optional |

| Impact | Meaning |
|--------|---------|
| low | annoying; user notices but ticket still shippable; fix in follow-up |
| medium | one phase needs redo; ticket delayed but not derailed |
| high | ticket fails; significant rework or scope change required |
| critical | shipped code would cause data loss, security breach, or user-facing crash |

The probability × impact combination drives **mitigation rigor**:

- low × low → log and ignore (acceptable noise)
- low × medium / medium × low → mention in plan; monitor
- medium × medium → explicit mitigation step in Phase 1.C/1.D
- low × high / high × low / medium × high → mandatory mitigation, escalation path documented
- high × medium / medium × critical / high × high / any × critical → **block ticket** until mitigation strategy is signed off by Architecture Veto Officer

### Rules

- **Minimum 0 risks, maximum ~8 per ticket.** Trivial tickets might genuinely have zero. If you find more than 8, you're either padding or the ticket scope is too large — escalate to scope split.
- **Each risk has a single owner.** Not a team. Not "QA in general." A specific role. If the role doesn't exist, the risk is unownable and needs reformulation.
- **No risk is "acceptable" without an explicit acceptance entry.** If mitigation is "accept and monitor," the register says so. Silent acceptance is not allowed.
- **Knowledge Loop integration is mandatory.** If `relevant-lessons.md` matched lessons in the consult phase, those lessons must show up as risks here (or be explicitly dismissed with reasoning). A lesson that says "X causes Y" is, by definition, a known risk for any ticket where X applies.

---

## Owner

The **Risk Officer** role (already exists in v1.0 as a cross-cutting supervisor under Department 9; the Knowledge Loop activates it for real now). The Risk Officer is responsible for:

- Driving the risk identification session at Phase 1.B
- Writing `risk-register.md`
- Enforcing format
- Refusing to accept vague risks
- Verifying each risk has a real owner
- Driving the reconciliation at Phase 1.G

In tickets where no Risk Officer is activated (Lite mode, S tickets), the Tech Director carries this responsibility.

---

## The risk identification session

This is the explicit step at Phase 1.B close. Not a chat, not a vibe — a session with structure.

### Input

- Discovery outputs (codebase understanding, dependency map, prior art)
- `relevant-lessons.md` from Knowledge Loop consult
- The user's intent and acceptance criteria
- The triaged ticket size (S/M/L/XL) and scope

### Process

The Risk Officer (or Tech Director in their absence) drives a structured walk:

**Pass 1: Lessons-driven risks.** For every matched lesson in `relevant-lessons.md`, ask: does it imply a risk in this ticket? If yes, write it up as R-N. (This is the most common source of risks in a studio that's been running awhile.)

**Pass 2: Domain-driven risks.** Walk these categories explicitly and ask "any specific risk here?":
- **API stability**: any Godot API this ticket relies on that has known instability or is recent?
- **Data loss**: does this ticket touch persistence, save data, project files? What could corrupt or lose user data?
- **Performance**: does this ticket touch hot paths, mobile targets, large data sets?
- **Platform compatibility**: multi-platform target? Mobile? Renderer-specific?
- **Security**: does this ticket process untrusted data, allow code execution, modify user files?
- **Scope creep**: is the user's intent fully understood, or are there reasonable interpretations that would explode the work?
- **Dependency**: external libraries, third-party plugins, MCP integrations that could fail?
- **Architectural**: are we building on assumptions that might not hold at scale (Manifesto Invariant 4 stuff)?

For each category, the answer is usually "no specific risk" and that's fine. The categories are prompts, not quotas.

**Pass 3: Adversarial risks.** The Devil's Advocate gets one explicit prompt: "what's not on this list that should be?" One pass. If they find a real risk, it goes in. If they're reaching, they say so.

### Output

`risk-register.md` in the ticket's audit trail. Format enforced.

---

## Integration with Phase 1.C (Architecture)

Phase 1.C produces 3 alternatives per the Innovation Engine. With Risk Register in hand, the alternatives evaluation gets a new dimension:

**For each alternative, evaluate against each open risk.**

The trade-off matrix gets a "Risk handling" row per risk:

| Risk | Alt A | Alt B | Alt C |
|------|-------|-------|-------|
| R1 (mobile rendering perf) | Mitigates fully | Mitigates partially | Doesn't address |
| R2 (save schema migration) | Doesn't apply | Mitigates fully | Mitigates fully |
| R3 (scope creep on settings UI) | Vulnerable | Mitigates | Mitigates |

This makes the architecture decision *explicitly* about risk handling, not just elegance. An alternative that's elegant but vulnerable to R1 (high probability × high impact) is structurally worse than a less elegant alternative that mitigates R1.

The Architecture Veto Officer at Phase 1.E checks: do the chosen alternative's mitigations cover the medium-and-above risks?

---

## Integration with Phase 1.D (Planning)

Each high-or-above risk's mitigation gets translated to one or more sub-tasks in the Phase 1.D plan. The plan explicitly cites: "Sub-task 4 mitigates R2 (save schema migration)."

This makes mitigations **work items**, not aspirations. If no sub-task implements a mitigation, the mitigation isn't real.

---

## Integration with Phase 1.G (Reconciliation)

At Phase 1.G, **before** lesson harvest, the Risk Officer reopens `risk-register.md` and adds a reconciliation section:

```markdown
## Reconciliation (Phase 1.G)

### R1 (mobile rendering perf)
**Outcome**: Mitigated — measured 56fps on reference Pixel 6, within budget.
**Evidence**: `profiling/r1-pixel6.txt`, performance gate L40 PASS.
**New risk surfaced?**: No.

### R2 (save schema migration)
**Outcome**: Materialized — schema change broke v1 saves during testing.
**How handled**: Migration logic added in sub-task 7, re-tested, now PASS.
**Evidence**: `audit/bug-hunt-2.md#defect-3`
**New risk surfaced?**: Yes — see R6 below.

### R3 (scope creep on settings UI)
**Outcome**: Ducked — user clarified intent in Phase 1.A turn, scope held.
**Evidence**: ticket turn-2 user response
**New risk surfaced?**: No.

## New risks surfaced during execution

### R6: Migration logic itself may fail on partially-corrupted v1 saves
**Probability**: medium
**Impact**: medium
**Category**: data-loss
**Description**: While fixing R2, discovered that v1 saves with missing fields fail migration. Falls back to default — acceptable but quiet (no user warning).
**Owner**: Save System Engineer
**Mitigation**: Logged as DEF-NNN (deferred-work tracker); next ticket adds explicit corrupted-save warning UI.
```

### Outcomes vocabulary

- **Mitigated**: the planned mitigation worked; risk did not materialize.
- **Materialized**: the risk happened; describe how it was caught and handled.
- **Ducked**: the risk turned out to be a false alarm or scope changed such that it doesn't apply.
- **Accepted**: the risk happened or persists; ticket explicitly chose not to mitigate (with reasoning).

### Required for close

- Every risk in the register has a reconciliation entry
- Materialized risks have evidence of how they were handled
- New risks surfaced during execution are added (numbered continuing from the highest R-N)
- New risks become entries to consider for the Deferred Work Tracker if they're not closed in this ticket

---

## Feed-forward to Knowledge Loop

Risks that materialized often become lessons. The Risk Officer collaborates with the Studio Knowledge Curator at Phase 1.G close:

- Did a materialized risk teach something reusable? → that's a lesson candidate
- Did a ducked risk teach that a category is over-weighted? → that's also a lesson candidate
- Did a new-risk-surfaced reveal a category the studio is blind to? → write a lesson

This makes Risk Register a **feeder** for the knowledge base, not just a consumer of it.

---

## Roles in the protocol

### Risk Officer (existing, now active)
- Drives risk identification session
- Owns `risk-register.md`
- Enforces format and ownership
- Drives reconciliation at Phase 1.G
- Reports materialized-risk patterns to Curator

### Tech Director (existing, expanded)
- Carries Risk Officer's role on Lite/S/M tickets where Risk Officer not activated
- At triage, decides whether the ticket needs full Risk Officer engagement

### Architecture Veto Officer (existing, expanded)
- At Phase 1.E, checks alternative-vs-risks coverage
- Vetoes architectures that leave medium-or-above risks unmitigated

### Devil's Advocate (existing, expanded)
- Final adversarial pass during risk identification
- One explicit prompt; not endless second-guessing

### Studio Knowledge Curator (existing, new collaboration)
- At Phase 1.G, collaborates with Risk Officer on lesson candidates from materialized risks

---

## Quality Gates

| Gate | Check | Owner |
|------|-------|-------|
| **L45** | `risk-register.md` exists at Phase 1.B close, format-valid | Risk Officer |
| **L46** | Every medium-or-above risk has a mitigation tied to a sub-task in Phase 1.D plan | Risk Officer + Tech Director |
| **L47** | Phase 1.C trade-off matrix includes risk-handling rows for medium-or-above risks | Trade-off Analyst |
| **L48** | Reconciliation section completed at Phase 1.G; every risk has an outcome | Risk Officer |
| **L49** | New-surfaced risks logged (in register and, if open, in Deferred Work Tracker) | Risk Officer |

---

## Cost-aware mode behavior

- **Lite (S tickets)**: Risk Register usually skipped. If Tech Director identifies even one medium-or-above risk during triage, ticket gets upgraded to Standard.
- **Standard (M, most L)**: Full protocol applies. Reasonable expectation: 0-4 risks per ticket.
- **Full (XL)**: Full protocol. Reasonable expectation: 3-8 risks per ticket. Reconciliation is more thorough; lessons-feed-forward is mandatory.

---

## What this protocol does NOT do

- It does not paralyze tickets with risk theater. A ticket with zero genuine risks has zero entries — that's correct, not a failure.
- It does not require predicting all unknowns. New risks surface during execution; that's expected. The reconciliation captures them.
- It does not punish materialized risks. Materializing a risk you predicted is correct — that's why you wrote it down. The studio is honest about what's uncertain.
- It does not replace Architecture Veto or Honesty Audit. It complements them by making the pre-execution context explicit.

---

## Why this is part of the intelligence layer

Without Risk Register, the studio enters execution blind to its own concerns. Engineers carry mental risks they don't share, the Tech Director makes architecture decisions without explicit threat analysis, and at ticket close nobody asks "what did we get away with this time?"

With Risk Register:
- Risks are surfaced before execution
- Architecture choices account for them
- Plans implement mitigations as work items
- Close reconciliation builds a track record of what materializes and what doesn't
- The Knowledge Loop gets fed real materialized-risk lessons, not just defect lessons

This is the second of the four v2.2 layers. It's the discipline of pre-production made visible.
