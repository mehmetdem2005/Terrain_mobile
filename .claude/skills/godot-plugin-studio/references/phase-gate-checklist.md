# Phase Gate Checklist

Concrete pass/fail criteria for each of the 7 phases in `multi-phase-execution-protocol.md`. Used by the role responsible for each phase's exit gate.

A phase that does not have every required item checked cannot advance. There is no "good enough" — partial passes return the ticket to that phase with specific findings.

---

## Phase 1.A — Understanding gate

Evaluator: **Producer + Tech Director** (joint sign-off)

| # | Check | How verified |
|---|-------|--------------|
| 1.A.1 | `intent-doc.md` exists | File present |
| 1.A.2 | User's verbatim request is preserved | Section in intent-doc |
| 1.A.3 | Every hard requirement is testable | Each requirement maps to a check that could be run |
| 1.A.4 | Out-of-scope list exists and is non-trivial | "Nothing" is rarely correct — push back |
| 1.A.5 | Unknowns list exists | If empty, ask "really nothing?" — there are always unknowns |
| 1.A.6 | Confidence stated honestly | "high" only if everything is unambiguous |
| 1.A.7 | If confidence is medium or low, user has been asked | Audit trail shows the question and user's response |

If any of 1.A.1–7 fails: ticket stays in 1.A. Cannot advance.

---

## Phase 1.B — Discovery gate

Evaluator: **Feasibility Analyst + API Verification Specialist** (joint)

| # | Check | How verified |
|---|-------|--------------|
| 1.B.1 | `feasibility-doc.md` exists | File present |
| 1.B.2 | Every required Godot capability is verified against 4.6.2 XML | grep evidence in feasibility-doc |
| 1.B.3 | Prior art search was conducted | Asset Library + GitHub queries logged |
| 1.B.4 | If prior art exists, evaluation is documented | "Why not use the existing one" or "We are using it" |
| 1.B.5 | All unknowns from 1.A have spike results | No "TBD" entries |
| 1.B.6 | Verdict is explicit (FEASIBLE / FEASIBLE WITH CAVEATS / INFEASIBLE) | One of three, no "probably" |
| 1.B.7 | If INFEASIBLE: ticket returned to 1.A for renegotiation | Audit trail shows return |
| **1.B.8** | **Pre-ticket Knowledge Loop consult performed (v2.2)** | `relevant-lessons.md` exists; matched lessons cited OR "no match" justified — Gate L43 |
| **1.B.9** | **Risk Register produced (v2.2)** | `risk-register.md` exists; format-valid; every medium-or-above risk has an owner and a planned mitigation — Gate L45 |

---

## Phase 1.C — Architecture gate

Evaluator: **Architecture Review Board** (3 seats — Tech Director + Principal Engineer + rotating)

| # | Check | How verified |
|---|-------|--------------|
| 1.C.1 | `architecture-doc.md` exists | File present |
| 1.C.2 | ≥3 alternatives evaluated | Section per alternative, none labeled "we just picked X" |
| 1.C.3 | Trade-off matrix completed | Comparison across maintainability, performance, complexity, mobile, time, risk |
| 1.C.4 | Module boundaries align with conceptual boundaries | Not artifacts of "this file got too long" |
| 1.C.5 | Each module has a single, expressible responsibility | Stated in one sentence per module |
| 1.C.6 | Inter-module coupling is intentional and documented | "Module A talks to B via signal X" — explicit |
| 1.C.7 | Lifecycle is fully designed | init, runtime, teardown, error paths all addressed |
| 1.C.8 | Public API surface is enumerated | Every symbol the user will touch |
| 1.C.9 | Dependencies are listed | External plugins, Godot subsystems, resources |
| 1.C.10 | Risks accepted are explicit | Each risk has a one-line justification |
| 1.C.11 | ADR(s) recorded for long-lived decisions | At least one ADR for any L/XL ticket |
| 1.C.12 | Design can be sketched as a diagram in <5 minutes | If you can't sketch it, it's too complex |
| 1.C.13 | ARB has voted | 3 votes recorded, dissent (if any) documented |
| **1.C.14** | **Ticket fingerprint produced (v2.2)** | `ticket-fingerprint.md` exists; every axis answered; relevant catalog categories summarized — Gate L50 |
| **1.C.15** | **Trade-off matrix includes risk-handling rows (v2.2)** | For every medium-or-above risk in Risk Register, the matrix has a row showing how each alternative handles it — Gate L47 |

If any of 1.C.1–13 fails: ticket stays in 1.C.

---

## Phase 1.D — Planning gate

Evaluator: **Producer + Tools Lead + Definition of Done Steward** (joint)

| # | Check | How verified |
|---|-------|--------------|
| 1.D.1 | `task-breakdown.md` exists | File present |
| 1.D.2 | Every architecture component from 1.C maps to ≥1 sub-task | Cross-reference; no orphan components |
| 1.D.3 | Every sub-task has an owner role | Not "TBD", not "someone" |
| 1.D.4 | Every sub-task has acceptance criteria | Testable, not vague |
| 1.D.5 | Dependency graph is acyclic | No A blocks B blocks C blocks A |
| 1.D.6 | Execution order identifies parallelizable vs sequential | At least one of each on L/XL |
| 1.D.7 | No sub-task says "implement everything else" | Decomposition is real, not a stub |
| 1.D.8 | Impact Analyzer has pre-scanned for cross-file dependencies | List of expected ripple targets exists |
| **1.D.9** | **Folder structure aligns with standard template** | Layout matches or justifiably deviates from `clean-architecture-manifesto.md` standard structure |
| **1.D.10** | **Every planned file has a one-phrase job** | No vague names (helpers, utils, main, manager alone); each file's purpose statable in one phrase |
| **1.D.11** | **System responsibilities are singular** | Each system has a one-sentence responsibility; no "and" conjunctions in the responsibility statements |
| **1.D.12** | **Cross-system communication plan documented** | Which signals between systems; which interfaces; no "reaching through" patterns planned |
| **1.D.13** | **Predictive checklist complete (v2.2)** | `predictive-checklist.md` exists; every relevant catalog category walked; APPLIES/DOESN'T APPLY decided per pattern; every APPLIES has a sub-task — Gate L51 |
| **1.D.14** | **Sub-tasks annotated with predictive coverage (v2.2)** | Every sub-task lists which predictive patterns it covers OR explicitly states "no patterns" — Gate L52 |
| **1.D.15** | **Medium-or-above risks have plan sub-tasks (v2.2)** | Every medium/high probability × medium/high/critical impact risk from Risk Register has at least one Phase 1.D sub-task tied to its mitigation — Gate L46 |

---

## Phase 1.E — Architecture Gate (the hard stop)

Evaluator: **Architecture Veto Officer** (see `architectural-veto-protocol.md`)

This gate evaluates the architecture *as a whole*, not individual checks. The Veto Officer asks one meta-question: **"Would a senior engineer at a real AAA studio approve this?"**

If yes → PASS. If no → FAIL with specific findings.

| # | Sub-question | Threshold |
|---|--------------|-----------|
| 1.E.1 | Are module boundaries conceptually clean? | No artifacts of expedience |
| 1.E.2 | Is coupling intentional? | Every cross-module call has a reason |
| 1.E.3 | Is the lifecycle fully designed? | All paths covered |
| 1.E.4 | Does the design accommodate likely extensions? | Adding a new feature shouldn't require restructuring |
| 1.E.5 | Can it be explained in <10 minutes? | If not, complexity is the problem |
| 1.E.6 | Are there any "we'll figure it out in 1.F" items? | These are red flags — return to 1.C |
| 1.E.7 | Is anything obviously over-engineered? | Excess abstraction is also a fail |
| 1.E.8 | Is the planned task breakdown faithful to the architecture? | 1.D must realize 1.C, not drift |

**Verdict:**
- ALL 8 satisfied → **PASS** → 1.F begins
- 1-2 weak items → **PASS WITH CONDITIONS** → conditions logged, 1.F begins with risks
- 3+ weak items, or any "obviously wrong" → **FAIL** → return to 1.C

This veto cannot be silently overridden. Studio Head + Tech Director both must co-sign, AND an auto-postmortem ticket is created.

---

## Phase 1.F — Execution gate

Evaluator: **Tools Lead** (per sub-task) + **Lead Tools Engineer** (overall)

| # | Check | How verified |
|---|-------|--------------|
| 1.F.1 | Every sub-task in 1.D is completed | Audit trail per sub-task |
| 1.F.2 | Each sub-task's acceptance criteria are met | Verification entry per ST |
| 1.F.3 | Each module passes its own parse + lint | `godot --check-only` + `gdlint` per file |
| 1.F.4 | No deviation from 1.C architecture | If there was deviation, 1.C was re-opened |
| 1.F.5 | Audit trail is complete | Every action logged |
| 1.F.6 | All blockers raised during 1.F are resolved | No open blockers |

---

## Phase 1.G — Integration gate

Evaluator: **Integration Engineer + Semantic Dependency Engineer + Consistency Auditor** (joint)

| # | Check | How verified |
|---|-------|--------------|
| 1.G.1 | `integration-report.md` exists | File present |
| 1.G.2 | Semantic dependency 7-question audit run for every new/changed concept | Per-concept entries |
| 1.G.3 | Every applicable semantic dependency rule from the catalog has been considered | Catalog check log |
| 1.G.4 | Every new public function has at least one caller | Wiring audit |
| 1.G.5 | Every new module is invoked from somewhere | Reverse wiring audit |
| 1.G.6 | Every new signal is emitted AND listened (or single-side documented) | Signal wiring log |
| 1.G.7 | Dead code scan returns zero new dead code | `scripts/dead-code-scan.sh` output |
| 1.G.8 | Cross-impact analysis is complete | List of touched files outside ticket scope + justification each |
| 1.G.9 | Every deferred item is in the Deferred Work Tracker | DEF-NNN entries created |
| 1.G.10 | Audit trail has no internal contradictions | Consistency Auditor scan |

---

## Override protocol for phase gates

Any phase gate can be overridden by:
1. **Tech Director signature** for 1.A-1.D and 1.F-1.G gates
2. **Studio Head + Tech Director joint signature** for 1.E (the architecture gate)

Every override requires:
- Written rationale in audit trail
- Entry in `.studio/knowledge-base/overrides.md`
- Auto-postmortem ticket created at ticket close
- Postmortem must evaluate whether the override should have happened

Overrides are tracked per role. A role that requests too many overrides goes on a PIP. The architecture gate (1.E) override is the most expensive — overriding it 2+ times in a quarter triggers a charter review.

---

## Phase metrics

Every ticket records phase metrics:
- Time spent per phase (rough — "Phase 1.C took ~30% of total")
- Gate verdict per phase (PASS / FAIL / PASS_WITH_CONDITIONS)
- Returns to earlier phases (how often did 1.E send us back to 1.C?)

These feed the Performance Analytics Engineer. Tickets that frequently return from 1.E to 1.C indicate either:
- The Plugin Design Lead's prompt needs amendment, or
- The Architecture Veto Officer's threshold is calibrated wrong

Either way, the data drives prompt improvement.
