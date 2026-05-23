# Role Authority Boundaries

The studio has ~100+ roles. Some have overlapping responsibilities. When two roles could both reasonably evaluate the same situation, **who decides?**

This document is the resolution. Each ambiguity gets a clear ownership rule. No more "but I thought you were the one who..." conversations.

This is not a re-org of roles. The role definitions in `01-executive-production.md` through `14-community-support.md` stand. This document is the authority-clarification layer on top.

---

## Why this exists

During v2.0 buildout, several role overlaps emerged organically:

- Honesty Auditor and Quality Gate Officer can both block sign-off
- Tools Lead and Lead Tools Engineer are different roles but easily confused
- Clean Code Officer and Architectural Quality Auditor both review code quality
- Architecture Veto Officer and Architectural Debt Auditor both evaluate architecture
- Bug Hunter Lead and Devil's Advocate can both raise issues
- Defect Pattern Specialist and Edge Case Hunter both find pre-emptive issues
- Semantic Dependency Engineer and Impact Analysis Engineer both check ripple effects

These aren't bugs — multiple perspectives often catch what one would miss. But when they conflict or when responsibility for a specific finding is unclear, the studio needs an answer.

---

## Authority resolution rules

### Honesty Auditor vs. Quality Gate Officer

| Situation | Authority |
|-----------|-----------|
| Unverified API claim | **Honesty Auditor** — primary; QGO supports |
| Failed parse check | **Quality Gate Officer** — gate criterion |
| Documentation drift from code | **Honesty Auditor** — honesty domain |
| Missing DoD item | **Quality Gate Officer** — DoD enforcement |
| Disagreement between the two | **Honesty Auditor's veto stands** — escalates to Tech Director only if QGO believes honesty assessment is wrong |

**Principle:** Honesty Auditor evaluates *truth of claims*; Quality Gate Officer evaluates *completion of process*. Truth wins over process.

### Tools Lead vs. Lead Tools Engineer

| Role | Scope |
|------|-------|
| **Tools Lead** | Department head for Tools Engineering. Assigns work, coordinates specialists, owns the department's overall output quality. |
| **Lead Tools Engineer** | Senior individual contributor. Writes complex code, mentors juniors, owns specific complex sub-systems. |

**Distinguishing test:** Tools Lead reads pull requests and makes go/no-go decisions on what ships from the department. Lead Tools Engineer writes pull requests for the complex parts and reviews others' work for technical correctness.

In small ticket contexts (S/M), often the same model instance plays both roles — the rule then: when wearing "Lead" hat, you're deciding; when wearing "Engineer" hat, you're building.

### Clean Code Officer vs. Architectural Quality Auditor

| Scope | Owner |
|-------|-------|
| Reading individual files for quality | **Clean Code Officer** |
| Walking the spaghetti pattern catalog | **Clean Code Officer** |
| Mapping the call graph across files | **Architectural Quality Auditor** |
| Verifying manifesto invariants (5 invariants) | **Architectural Quality Auditor** (with Clean Code Officer reading individual evidence) |
| Per-criterion qualitative review (cohesion, naming, etc.) | **Clean Code Officer** |
| "Doesn't fall apart" test | **Architectural Quality Auditor** |
| Module boundary analysis | **Architectural Quality Auditor** |

**Principle:** Clean Code Officer = file-level reader. Architectural Quality Auditor = system-level mapper. Both run in Phase 1.G; their reports are separate; both must PASS for the gate.

### Architecture Veto Officer vs. Architectural Debt Auditor

| Situation | Owner |
|-----------|-------|
| New ticket, Phase 1.E | **Architecture Veto Officer** — evaluates proposed design |
| Audit/refactor ticket on existing codebase | **Architectural Debt Auditor** — evaluates code-as-built |
| Mid-ticket design change request | **Architecture Veto Officer** — re-evaluates the amended design |
| User asks "should we rewrite this?" | **Architectural Debt Auditor** — produces TACTICAL/STRATEGIC/SYSTEMIC verdict |
| User asks "is this design good?" pre-implementation | **Architecture Veto Officer** |
| Both roles disagree on whether a rewrite is needed | **Studio Head** decides; both reports presented to user |

**Principle:** Veto Officer judges designs *before* code; Debt Auditor judges code *after* (or in existing-codebase audits).

### Bug Hunter Lead vs. Devil's Advocate

| Activity | Owner |
|----------|-------|
| Convene Adversarial Hunt | **Bug Hunter Lead** |
| Generic adversarial perspective on a design | **Devil's Advocate** |
| Walk defect catalog | **Defect Pattern Specialist** (under Bug Hunter Lead) |
| "What if the user does X unexpectedly?" | **Devil's Advocate** + **Edge Case Hunter** |
| Concurrency-specific issues | **Concurrency Bug Specialist** (under Bug Hunter Lead) |
| Found a bug — who logs it? | The finder logs it; **Bug Hunter Lead** consolidates per-ticket |

**Principle:** Bug Hunter Lead runs the offensive hunt; Devil's Advocate is a general-purpose questioner who participates in hunts but also operates outside them (e.g., during Phase 1.C alternative review).

### Defect Pattern Specialist vs. Edge Case Hunter

| Finding type | Owner |
|--------------|-------|
| "This matches a known defect pattern in Godot 4.6.2" | **Defect Pattern Specialist** (catalog match) |
| "This will fail at boundary conditions (null, zero, max int, empty string)" | **Edge Case Hunter** |
| "This will fail when run twice / reloaded / in a sequence" | **Concurrency Bug Specialist** |
| "This will fail when called from an unexpected context" | **Devil's Advocate** |

**Principle:** Catalog patterns belong to Defect Pattern Specialist; novel edges belong to Edge Case Hunter. Findings that don't fit cleanly go to Bug Hunter Lead for routing.

### Semantic Dependency Engineer vs. Impact Analysis Engineer

| Question | Owner |
|----------|-------|
| "Did I forget the matching disconnect for this connect?" | **Semantic Dependency Engineer** (catalog rule A1) |
| "If I rename foo to bar, which call sites break?" | **Impact Analysis Engineer** (grep) |
| "Adding a diff texture — what about normal map?" | **Semantic Dependency Engineer** (catalog rule E1) |
| "I changed this function's signature, which callers need updating?" | **Impact Analysis Engineer** (grep + manual inspection) |

**Principle:** Semantic = conceptual dependencies you have to think about; syntactic = symbol dependencies grep can find. Both run in Phase 1.G; they coordinate but own different finding types.

### Integration Engineer vs. Dead Code Hunter vs. Orphan Reference Hunter

| Finding | Owner |
|---------|-------|
| "This new public function has no callers" | **Integration Engineer** (forward wiring) |
| "This file is never preloaded/loaded/referenced" | **Integration Engineer** (reverse wiring) OR **Dead Code Hunter** (depending on scope) |
| "This old function in an unchanged file isn't called anymore" | **Dead Code Hunter** (existing code may have become dead) |
| "This preload path points to a missing file" | **Orphan Reference Hunter** |
| "This connect targets a method that doesn't exist" | **Orphan Reference Hunter** |

**Practical rule:** Integration Engineer focuses on the new code in this ticket; Dead Code Hunter scans the whole codebase for what may have died; Orphan Reference Hunter scans for references to nothing.

In practice, the trio works closely. The roles separate cleanly only on contested findings — most findings are obvious which role owns them.

### Tech Director vs. Studio Head

| Decision | Owner |
|----------|-------|
| Ticket triage (size, mode, role activation) | **Tech Director** |
| L-tier sign-off | **Tech Director** |
| XL-tier sign-off | **Studio Head** |
| Override of Architecture Veto Officer | **Studio Head + Tech Director jointly** |
| Override of Honesty Auditor | **Studio Head + Tech Director jointly** |
| Role activation in unprecedented situation | **Tech Director** |
| Architectural rewrite recommendation accepted? | **User** decides; Studio Head presents the case |
| Performance review of a role's prompts | **Tech Director** (with Performance Analytics Engineer's data) |
| Studio-wide policy change | **Studio Head** |

### When the cross-cutting supervisors disagree

Cross-cutting supervisors (Honesty Auditor, Consistency Auditor, Devil's Advocate, Quality Gate Officer, etc.) all have veto authority within their domain. If two veto:

1. Both findings logged
2. Tech Director reviews — are the findings about the same thing or different things?
3. If same thing: resolve which framing is correct (often both are right; engineer addresses both)
4. If different things: both must be addressed before sign-off

The studio does not pick sides between supervisors. Both findings stand.

---

## Roles by single-decision domain

For quick reference, the highest-authority role for each common decision type:

| Decision | Highest authority |
|----------|-------------------|
| Is this API claim verified? | Honesty Auditor |
| Is the architecture sound? | Architecture Veto Officer (design) / Architectural Quality Auditor (built) |
| Is the code clean? | Clean Code Officer |
| Is the manifesto satisfied? | Architectural Quality Auditor |
| Is wiring complete? | Integration Engineer |
| Are there bugs we missed? | Bug Hunter Lead |
| Are there dominoes we missed? | Semantic Dependency Engineer |
| Are there callers we missed? | Impact Analysis Engineer |
| Is the ticket scoped correctly? | Producer (with Tech Director triage) |
| Is the user's intent honored? | Producer (Phase 1.A owner) + End-User Advocate |
| Should this ship? | Tech Director (L) / Studio Head (XL) |
| Should we rewrite? | Architectural Debt Auditor recommends; Studio Head presents; User decides |
| Was a defer-decision correct? | Audit Trail Officer (process) / Deferral target's owner role (content) |

---

## Veto chains

The studio has multiple vetoes. The order of precedence:

1. **Honesty Auditor** — any unverified claim blocks sign-off. Highest priority because untruth contaminates everything else.
2. **Architecture Veto Officer (1.E)** — second priority. No code is written until the design passes.
3. **Architectural Quality Auditor** — third. The built code must match design intent and manifesto.
4. **Clean Code Officer** — fourth. Spaghetti at the file level blocks even if architecture is OK.
5. **Integration Engineer + Dead Code Hunter** — fifth. Wiring must be clean.
6. **Bug Hunter Lead's findings** — variable; P0/P1 block sign-off; P2/P3 may defer.
7. **Quality Gate Officer** — final check; gates the formal sign-off.

A veto at any level returns the ticket to the appropriate phase. The user sees a summary of what was caught; the studio doesn't bury internal disagreement.

---

## Anti-patterns to avoid

The role system can degrade in predictable ways:

### Anti-pattern: rubber-stamp roles

A role consistently signs off without finding anything. This is suspicious. The Performance Analytics Engineer flags roles whose pass-rate is anomalously high.

Possible causes:
- Role's prompt is too soft (revise)
- Role's scope doesn't apply to the tickets it's being run on (rescope)
- Studio is selecting away the tickets that would surface findings (triage check)

### Anti-pattern: role inflation

Adding a new role for every novel situation. The studio caps role count growth: each new role added must demonstrate that an existing role couldn't reasonably cover the situation.

`role-instantiation-protocol.md` governs new role creation. The bar is "we genuinely need this; no existing role's scope can be stretched."

### Anti-pattern: territorial roles

Two roles refusing to coordinate because "that's the other one's job." The studio resolves with the rules in this document. Where they don't, Tech Director resolves directly.

### Anti-pattern: bypass roles

Engineers learning which roles are "easy" and routing work to them. The Tech Director's triage is fixed; engineers don't pick their reviewers.

---

## How to consult this document

When you find yourself thinking "who decides this?":

1. Search this document for the closest matching situation
2. Apply the rule
3. If no match: ask Tech Director; they decide and the answer becomes a new rule in this document

The document grows from real cases, not theoretical ones.

---

## When two roles produce contradictory findings

Genuine contradiction (not just different framings):

1. Both findings stay in the audit trail
2. The engineer is responsible for resolving the contradiction:
   - Demonstrate one finding is wrong (with evidence)
   - OR address both
3. If unresolved: Tech Director adjudicates
4. The resolution is logged as a new entry in this document if the situation is likely to recur

This is how the studio's institutional knowledge compounds.
