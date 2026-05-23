# Rollback Strategy Protocol (v2.2)

The studio's protocol for **recognizing that the current execution path is wrong, and returning to a checkpoint** — without sunk-cost paralysis blocking the call.

This is the final intelligence layer. Knowledge Loop makes the studio remember. Risk Register makes it name risks. Predictive Prevention makes it anticipate patterns. Rollback Strategy makes it **course-correct mid-flight**.

The user's underlying demand: a stubborn studio that ploughs forward into a known-bad direction is not AAA. AAA studios recognize when they've over-committed, count the cost of continuing vs. reverting, and choose deliberately — never by inertia.

---

## What's broken without this protocol

In v2.1, the studio commits to an architectural direction at Phase 1.E (Architecture Veto Officer's gate). From there, Phase 1.F (Execution) proceeds with optimism. Honesty Auditor is passive — they only speak when asked, and the questions they get tend to be about specific defects, not about wholesale-wrong-direction.

This means:

- A flawed architectural choice that passes Phase 1.E is committed to for the rest of the ticket
- An execution that's diverging from the design doc is sometimes noticed but rarely acted on
- "We've already spent 2 hours, we can't go back" is a sentence the studio implicitly accepts
- The Architectural Debt Auditor exists but is mostly post-hoc; not "stop now and reverse"

The result: tickets occasionally ship the wrong thing well-built, instead of the right thing rebuilt. The user gets a clean-looking deliverable that's structurally on the wrong path.

In v2.2 with this protocol, the studio has:

1. **Checkpoint snapshots** at every phase boundary — explicit "this is where we were"
2. **Reversal triggers** — concrete signals that should pause execution
3. **Rollback decision protocol** — structured comparison of continuing vs reverting
4. **Sunk-cost veto** — Honesty Auditor's explicit power to reject "but we already worked X hours"
5. **Rollback audit trail** — when a rollback happens, the reasoning is permanent

---

## The four parts

### Part 1 — Checkpoint snapshots
### Part 2 — Reversal triggers
### Part 3 — Rollback decision protocol
### Part 4 — Sunk-cost veto

Each has an owner, a gate, and explicit integration with prior v2.2 layers.

---

## Part 1 — Checkpoint snapshots

At every phase boundary (1.A→1.B, 1.B→1.C, 1.C→1.D, 1.D→1.E, 1.E→1.F, 1.F→1.G, 1.G→close), a checkpoint snapshot is recorded. This is what makes rollback possible — without checkpoints, "going back" means redoing everything blind.

### What a checkpoint captures

```
.studio/checkpoints/TKT-NNN-phase-1.X/
├── ticket-state.json              # Ticket status snapshot
├── audit-trail-snapshot.md        # Audit trail up to this point
├── artifacts/                     # Phase artifacts (intent-doc, feasibility-doc, etc.)
│   └── ...
├── code-state-manifest.md         # If code exists: list of files + line counts + hashes
└── checkpoint-summary.md          # 1-paragraph: "where the ticket is, what's decided, what's still open"
```

### Owner

**Audit Trail Officer** (existing role) automatically creates checkpoints. The studio cannot opt out of checkpointing — it's how rollback becomes mechanically possible.

For S/M tickets in Lite/Standard mode, checkpoint contents are minimal (ticket state + summary). For L/XL tickets in Standard/Full mode, full artifact snapshots.

### Why this matters

A rollback to "Phase 1.C — alternative B was chosen, we picked A" requires knowing what alternative B's design doc looked like. Without checkpoints, that information is lost as work moves forward — even though Phase 1.C's `architecture-doc.md` shows the 3 alternatives, the *reasoning* and *what's-been-built-since* exists only at the moment of checkpointing.

Checkpoints are the studio's "save game." Without them, the studio is single-checkpoint Dark Souls.

### Gate

**L54 — Checkpoints exist for every completed phase boundary**. At Phase 1.G close, every prior phase boundary has a populated checkpoint directory. If any checkpoint is missing, Phase 1.G cannot close — checkpointing failure is a process defect.

---

## Part 2 — Reversal triggers

Concrete signals that should pause execution and convene a rollback decision. These are not vibes — they are enumerable, observable, and tied to specific roles.

### The trigger list

Triggers fall into four categories. Any one trigger is sufficient to convene a rollback decision; it does not require multiple to align.

**Category A: Architectural divergence**
- A1: The code under construction diverges from the Phase 1.C architecture-doc in a way that would not have passed the Architecture Veto if reviewed today. (Owner: Architecture Veto Officer, even though normally only active at Phase 1.E.)
- A2: A Manifesto Invariant (1-5) is being violated and the violation isn't isolated — it's structural to the current direction.
- A3: The Clean Architecture Auditor finds that the "doesn't fall apart when it grows" test is now failing on the in-progress code.

**Category B: Risk realization**
- B1: A high-or-above risk from Risk Register has materialized AND its mitigation isn't working.
- B2: A risk not in the Risk Register has materialized with high impact — and was foreseeable, meaning the risk identification missed it for non-novel reasons.
- B3: Multiple medium risks have materialized in the same ticket — suggesting the architecture choice was poorly matched to the actual problem.

**Category C: Predictive failure**
- C1: 3+ unpredicted defect-pattern matches found in Phase 1.G — fingerprint missed the ticket's surface.
- C2: A repeat-mistake alarm (Knowledge Loop L44) AND the lesson was clearly applicable AND no one consulted it AND it was a high-impact lesson. (This is a process AND architectural failure compounding.)

**Category D: Honest-auditor-summoned**
- D1: Honesty Auditor convenes a rollback consideration based on overall pattern of evasions, over-claims, or fabrication signals during execution. This is a discretionary trigger — Honesty Auditor's call.
- D2: Devil's Advocate raises a "I told you so" — a concern they raised at Phase 1.C/1.D that was dismissed and is now visibly happening.

### How triggers fire

When a role observes a trigger, they file a **rollback request** in the ticket audit trail:

```markdown
## Rollback Request — TKT-NNN — by <role> at <phase>

**Trigger fired**: <ID, e.g., A2>

**Observation**: <2-3 sentences. What was observed, when, where.>

**Why this is a rollback signal vs a normal defect**: <Why this isn't just "fix it in place" — what about it suggests the direction itself is wrong.>

**Proposed rollback target**: <Which checkpoint to consider returning to, and why.>

**Estimated rework if continuing forward**: <Rough estimate>
**Estimated rework if rolling back to proposed target**: <Rough estimate>
```

This request triggers Part 3 — the rollback decision protocol.

### Gate

**L55 — Rollback triggers monitored**. At Phase 1.G close, the audit trail shows that triggers were watched throughout execution. Either no triggers fired (and that's documented as part of the close review) OR triggers fired and were processed via Part 3.

---

## Part 3 — Rollback decision protocol

When a rollback request is filed, the studio doesn't immediately rollback. It also doesn't immediately reject. It runs a structured decision.

### Convening

When a rollback request comes in, the **Rollback Officer** (new role — see "Roles" below) convenes a rollback decision session within the same ticket session. Phase 1.F (or whichever phase the ticket is in) is paused.

Attendees (mandatory):
- The role who filed the request
- Tech Director
- Honesty Auditor
- Architecture Veto Officer (if the trigger is Category A)
- Risk Officer (if the trigger is Category B)
- Defect Pattern Specialist (if the trigger is Category C)
- Devil's Advocate (always)

### Decision dimensions

The session walks five dimensions explicitly, documenting answers:

**1. Validity of the trigger**
- Is the trigger observation accurate?
- Is it a real architectural/risk/predictive signal, or a normal in-progress defect?
- Devil's Advocate stress-tests the validity.

If the trigger is invalid: close the request with reasoning, resume execution.

**2. Scope of the problem**
- Is the problem localized (a sub-task) or systemic (the whole direction)?
- If localized: this is a defect, not a rollback signal. Close the request and treat as Phase 1.G item.
- If systemic: continue.

**3. Cost of continuing forward**
- Estimated rework to fix in place
- Probability the fix works
- Downstream consequences if the structural issue compounds

**4. Cost of rolling back**
- To which checkpoint? (1.D? 1.C? 1.B?)
- What gets thrown away?
- What gets preserved?
- How much of the in-progress work is reusable on the new path?

**5. Decision**
- One of: **CONTINUE** (trigger acknowledged but cost-benefit favors forward), **PARTIAL ROLLBACK** (return to a specific sub-task, redo only that), **FULL PHASE ROLLBACK** (return to a phase checkpoint, redo from there), **TICKET RESTART** (extreme — return to Phase 1.A and re-plan).

### Decision output

The session produces `rollback-decision.md`:

```markdown
# Rollback Decision — TKT-NNN

## Trigger reviewed
Original request: <link>
Filed by: <role>

## Validity assessment
<Devil's Advocate's findings>

## Scope assessment
<Localized | Systemic>

## Cost analysis

### Continuing forward
- Estimated remaining work: <hours/sessions>
- Estimated probability of success: <%>
- Risks if continuing: <list>

### Rolling back to <target>
- Work discarded: <list>
- Work preserved: <list>
- Estimated rework: <hours/sessions>
- New estimated probability of success: <%>

## Decision
**Verdict**: <CONTINUE | PARTIAL ROLLBACK | FULL PHASE ROLLBACK | TICKET RESTART>

**Reasoning**: <2-4 sentences. WHY this decision, given the cost analysis.>

**If rolling back**:
- Target checkpoint: <path>
- What carries forward: <list>
- What is redone: <list>
- New starting phase: <Phase 1.X>

**Sign-offs**: <list of attending roles + their concurrence or dissent>

**Dissent** (if any): <documented>
```

### Why a structured session vs intuition

Rollback decisions made on gut feel skew toward continuation (sunk cost). Rollback decisions made with structured cost analysis often reveal that continuation costs more than rollback — but only when the numbers are actually estimated, not felt.

This is why the session is mandatory: it forces the comparison to be explicit. The studio cannot say "we'll just push through" without writing down what "pushing through" costs.

### Gate

**L56 — Rollback decisions are structured**. Any rollback request produces a `rollback-decision.md` with all five dimensions filled. A decision to CONTINUE is valid IF the reasoning is documented; "we just decided to continue" is not acceptable.

---

## Part 4 — Sunk-cost veto

The Honesty Auditor's expanded authority. This is what prevents Part 3 from degenerating into rationalization.

### The forbidden argument

In any rollback decision session, the following argument is **explicitly forbidden**:

> "But we've already spent N hours / done X work / committed to Y direction — rollback wastes that effort."

This is sunk-cost reasoning, and it is the most common bias in over-committed studios.

The Honesty Auditor has the explicit power to **veto** any continuation decision that relied on sunk-cost reasoning. The veto looks like this:

```markdown
## Honesty Audit — Rollback Decision Review

The continuation decision in `rollback-decision.md` cited sunk-cost reasoning in:
- <quote from cost analysis>

This is forbidden under sunk-cost veto. The continuation decision is **rejected**. The session must re-evaluate using only forward-looking cost analysis.

If the continuation decision survives a forward-looking re-analysis, this veto is lifted.
```

### Legitimate vs sunk-cost reasoning

Distinguishing carefully because the line is sometimes subtle:

**Legitimate forward-looking reasoning** (allowed):
- "The completed work is reusable on the forward path; throwing it away costs ≥ rework."
- "The architecture is salvageable; the issue is one sub-component; in-place fix is cheaper."
- "The rollback would land us at a checkpoint that has its own known issues; we'd just retrace."

**Sunk-cost reasoning** (forbidden):
- "We already spent X hours."
- "We can't waste the work we've done."
- "Rolling back would be embarrassing / look bad."
- "The user has been waiting; we should ship something."

The difference: legitimate reasoning is about the *future* cost-benefit. Sunk-cost reasoning is about the *past* effort. The Honesty Auditor's job is to mark the difference and reject the latter.

### Gate

**L57 — No sunk-cost reasoning in rollback decisions**. Honesty Auditor reviews every `rollback-decision.md` for sunk-cost arguments. If found, the decision is vetoed and re-evaluated.

---

## What happens on rollback

When the decision is PARTIAL ROLLBACK, FULL PHASE ROLLBACK, or TICKET RESTART:

1. The target checkpoint is loaded — artifacts restored to that state
2. Audit trail records the rollback as a permanent event (not erased; "we went back" is part of the ticket's history)
3. A `post-rollback.md` is written: what's being changed in the new attempt vs the prior attempt
4. Execution resumes from the checkpoint
5. The next attempt has the prior attempt's lessons in front of it — this is a Knowledge Loop interaction; rollback teaches

### Multiple rollbacks

A ticket that rolls back twice triggers an automatic Studio Head review. Two rollbacks suggests either:
- The ticket scope is wrong (intake failure)
- The studio is missing a capability for this kind of work (training/role failure)
- The user's request is genuinely under-specified (Phase 1.A failure)

Multiple rollbacks aren't bad in themselves — they're a signal. The signal gets investigated.

---

## Roles in the protocol

### Rollback Officer (new role)

Department: Cross-Cutting Supervisors (alongside Honesty Auditor, Devil's Advocate)

**Charter**: You convene and run rollback decision sessions when a rollback request is filed. You are not the one who decides — you facilitate the decision. Your job is to ensure all five dimensions get walked, all attendees get heard, dissent is documented, and the decision document is honest.

You explicitly do NOT have veto power over the decision. Honesty Auditor has the sunk-cost veto; you do not have a substantive veto. Your authority is procedural: the session happens, the dimensions are walked, the decision is recorded.

**When you activate**: When any role files a rollback request.

**Key skill**: Resisting the pressure to "just decide." Your job is to make sure the decision is structured even when everyone wants to skip to the answer.

### Audit Trail Officer (existing, expanded)

Now responsible for automatic checkpoint creation at every phase boundary. Cannot opt-out.

### Honesty Auditor (existing, expanded authority)

Sunk-cost veto power added. Also a discretionary trigger filer (D1).

### Architecture Veto Officer (existing, expanded)

Available outside Phase 1.E for trigger filing in Category A.

### Devil's Advocate (existing, expanded)

Mandatory attendee at every rollback decision session. Validity tester for triggers.

### Risk Officer / Defect Pattern Specialist (existing, expanded)

Conditional attendees based on trigger category.

---

## Quality Gates

| Gate | Check | Owner |
|------|-------|-------|
| **L54** | Checkpoints exist for every completed phase boundary in this ticket | Audit Trail Officer |
| **L55** | Rollback triggers were monitored throughout execution (either no fires, or fires processed via L56) | Rollback Officer |
| **L56** | Any rollback request produced a structured `rollback-decision.md` with all five dimensions | Rollback Officer |
| **L57** | No sunk-cost reasoning survived in any continuation decision (Honesty Audit review) | Honesty Auditor |

---

## Integration with prior v2.2 layers

This protocol is the capstone. It uses everything before:

**From Knowledge Loop**:
- A repeat-mistake alarm (L44) is a Category C trigger (C2)
- Rollback decisions become lesson candidates — "we should have rolled back sooner because X" is a high-value lesson
- The lesson index can be consulted for "did we roll back on this kind of issue before? What was the outcome?"

**From Risk Register**:
- Materialized risks above mitigation expectation are Category B triggers (B1, B2, B3)
- The risk register's `escalation trigger` field becomes the early warning for B-class rollback signals
- Risk reconciliation at Phase 1.G includes whether a rollback was warranted but missed

**From Predictive Prevention**:
- Unpredicted-match clusters are Category C triggers (C1)
- The fingerprint accuracy review feeds into "did we set ourselves up for an unnecessary rollback risk by under-fingerprinting?"

**Into Phase Gates**:
- Phase 1.G adds L54-L57 checks
- Phase 1.E (Architecture Veto) is no longer the only "stop and reconsider" gate — any phase can trigger rollback now

---

## Cost-aware mode behavior

- **Lite (S tickets)**: Checkpoint snapshots are minimal (just ticket state + summary). Rollback decisions are simplified — Tech Director makes them solo with Honesty Auditor available for sunk-cost veto.
- **Standard (M, most L)**: Full protocol applies. Checkpoints are reasonably complete.
- **Full (XL)**: Full protocol with extra rigor. Devil's Advocate is explicitly assigned to monitor for triggers throughout execution, not just attend decisions.

---

## What this protocol does NOT do

- It does not encourage rollback. The default is forward execution. Rollback is a deliberate exception, not a routine option.
- It does not require rollback when triggers fire. Triggers convene a decision; the decision may be CONTINUE.
- It does not eliminate stubbornness. A studio that wants to push through can document why and continue. The protocol ensures that decision is conscious, not inertial.
- It does not punish rollback. A ticket that rolls back and ships well is better than a ticket that doesn't roll back and ships wrong.

---

## What this protocol explicitly DOES

- Makes "wrong direction" an observable, processable event
- Forbids sunk-cost reasoning as a continuation justification
- Creates audit-trail history of rollback decisions for future tickets to learn from
- Gives Honesty Auditor expanded authority to enforce honest cost analysis
- Closes the v2.2 intelligence layer

---

## Why this completes the intelligence layer

The studio now has the four capacities of a senior, mature engineering organization:

1. **Memory** (Knowledge Loop) — the studio knows what it learned
2. **Foresight** (Risk Register) — the studio names what could go wrong before it does
3. **Pattern anticipation** (Predictive Prevention) — the studio uses its catalogs as instruments, not graveyards
4. **Course correction** (Rollback Strategy) — the studio recognizes when it's wrong and changes direction without sunk-cost paralysis

Without all four, intelligence is partial:
- Memory without foresight: the studio reacts to known problems but doesn't predict them
- Foresight without pattern anticipation: the studio worries but doesn't systematically scan
- Pattern anticipation without course correction: the studio sees problems coming but ploughs into them anyway
- Course correction without memory: the studio reverses but doesn't learn why it was wrong

All four together: the studio that v2.2 was designed to be.

This is the end of the v2.2 protocol set. The studio is now structurally capable of behaving like an AAA team — not because it's perfect, but because the protocols force the behaviors that distinguish AAA from hopeful.
