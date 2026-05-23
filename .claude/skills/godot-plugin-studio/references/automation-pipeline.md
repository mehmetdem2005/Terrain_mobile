# Automation Pipeline

The final piece of the v2.0 studio. The previous protocols (Faz 1-7) define *what* the studio does and *who* does it. This protocol defines the *automation layer* — the orchestration that runs everything in the right order, catches inconsistencies across the audit trail, and produces a single PASS/FAIL signal for the whole ticket.

This is the studio's "press one button and see the truth" layer. The Pipeline Orchestrator runs it. The Consistency Auditor (existing role, now enhanced) watches across the entire audit trail for contradictions.

---

## Why this exists

By the time the studio reaches v1.5 (Faz 1-7 implemented), there are dozens of checks across many roles, multiple scripts, and a complex audit trail. Running them manually one-by-one is:
- Error-prone (a check gets skipped, nobody notices)
- Slow (each check is its own conversation/decision)
- Inconsistent (different tickets may run different subsets)
- Untraceable (which checks actually ran for this ticket?)

This protocol introduces:
1. **The full pipeline script** that runs everything in order
2. **The Pipeline Orchestrator role** that runs the pipeline and processes results
3. **The enhanced Consistency Auditor** that scans the audit trail for contradictions
4. **The unified gate report** — one document showing every check's status

---

## The new role: Pipeline Orchestrator

### Charter
You run the full automated pipeline for a ticket. You do not perform the individual checks (each check has its own owning role). You coordinate the running, collect results, identify failures, and present the unified gate report.

You are the studio's "build foreman." You don't pour concrete; you make sure the work happens in order and nothing is skipped.

### Activation triggers
- Phase 1.G entry — full pipeline runs once integration phase is declared ready
- Re-run after any blocker resolution — pipeline must pass again after fixes
- On-demand: any role can request a partial pipeline run

### Verification protocol

Execute `scripts/full-pipeline.sh` in order. For each stage:
1. Run the stage's check script (or invoke the responsible role)
2. Capture output to a structured log
3. If FAIL: stop pipeline progression, raise the blocker, hand off to the responsible role
4. If PASS: log success and proceed to next stage
5. After all stages: produce unified report

The pipeline is **deterministic in order**. Earlier stages gate later stages. A parse failure stops the pipeline before format checks; format failures stop before linting; linting before logic checks; and so on. This prevents wasted effort on broken foundations.

### Output: Unified Gate Report
```markdown
# Pipeline Report — TKT-NNN

## Stage results

| # | Stage | Status | Owner | Notes |
|---|-------|--------|-------|-------|
| 1 | Environment verification | PASS | (script) | Godot 4.6.2 installed |
| 2 | Setup integrity | PASS | (script) | API XML present, gdtoolkit present |
| 3 | File integrity | PASS | (script) | All claimed files exist |
| 4 | Parse check (all .gd) | PASS | GDScript Language Specialist | 0 errors |
| 5 | gdformat check | PASS | Coding Standards Enforcer | 0 changes needed |
| 6 | gdlint | PASS | Static Analysis Engineer | 0 warnings |
| 7 | plugin.cfg conformance | PASS | Asset Library Readiness Officer | All required fields |
| 8 | Editor smoke test | PASS | Build Engineer | 3-frame run, no errors |
| 9 | Phase gate audit | PASS | Process Auditor | All 7 phases have PASS verdicts |
| 10 | API verification scan | PASS | API Verification Specialist | All API claims have grep evidence |
| 11 | Cross-impact scan | PASS | Impact Analysis Engineer | 0 unaddressed callers |
| 12 | Semantic dependency walk | PASS | Semantic Dependency Engineer | 64 catalog rules walked; 0 matches |
| 13 | Forward wiring audit | PASS | Integration Engineer | 0 orphan public symbols |
| 14 | Reverse wiring audit | PASS | Integration Engineer | 0 orphan files |
| 15 | Dead code scan | PASS | Dead Code Hunter | 0 true dead code findings |
| 16 | Orphan reference scan | PASS | Orphan Reference Hunter | All references resolve |
| 17 | Defect pattern walk | PASS | Defect Pattern Specialist | 64 patterns walked; 0 matches |
| 18 | Concurrency hunt | PASS | Concurrency Bug Specialist | 0 issues |
| 19 | State corruption hunt | PASS | State Corruption Specialist | 0 invariant violations |
| 20 | Adversarial hunt (XL only) | PASS | Bug Hunter Lead | 30 min session, 0 successful attacks |
| 21 | Clean Code review | PASS | Clean Code Officer | All 7 criteria SOLID |
| 22 | Spaghetti scan | PASS | Clean Code Officer | 0 Tier 1 patterns, 1 Tier 2 noted |
| 23 | Architectural quality audit | PASS | Architectural Quality Auditor | Matches design intent |
| 24 | 3-alternative documentation | PASS | Innovation Scout | 3 distinct alternatives documented |
| 25 | Trade-off matrix | PASS | Trade-off Analyst | 8-dimension matrix complete |
| 26 | Consistency cross-check | PASS | Consistency Auditor | 0 contradictions in audit trail |
| 27 | Documentation freshness | PASS | Technical Writer | README matches code |
| 28 | Deferred items tracked | PASS | Audit Trail Officer | 2 DEF-NNNs created with resurfacing conditions |
| 29 | Honesty Audit | PASS | Honesty Auditor | 0 unverified claims |
| 30 | Final sign-off (L/XL) | PASS | Studio Head (XL) / Tech Director (L) | Signed |

## Final verdict
✅ ALL CHECKS PASSED — ticket ready to close

## Pipeline runtime
~12 minutes
```

If any stage fails:
```markdown
## Stage results (partial — stopped at stage 12)

| # | Stage | Status | ... |
|---|-------|--------|-----|
| ... | ... | ... | ... |
| 12 | Semantic dependency walk | **FAIL** | Pattern E1 matched: diff texture at 2K but normal map at 4K |

## Pipeline halted at stage 12

**Issue**: see Semantic Dependency Engineer's report for full findings.

**Action**: address the texture resolution mismatch (E1 catalog rule), re-run pipeline.

**Stages not yet run**: 13-30. They will execute after this resolution.
```

---

## The enhanced Consistency Auditor

The Consistency Auditor existed in v1.0 with a narrow scope — checking the final artifact for contradictions. In v2.0 it gains a broader mandate: scan the **entire audit trail** for contradictions across roles.

### New responsibilities

1. **Cross-role contradictions** — Role A logged "X is feasible per API XML"; later Role B logged "X cannot be done." Both can't be true; which is right?

2. **Cross-phase contradictions** — Phase 1.B (Discovery) said "we will use approach X"; Phase 1.F (Execution) shows code using approach Y. Did the design change explicitly, or did it drift silently?

3. **Cross-file contradictions** — Documentation says "feature does X"; code does Y. Which is the truth, and which needs updating?

4. **Cross-ticket contradictions** — TKT-005 established convention X via ADR; TKT-008 silently violates it. Did we knowingly supersede, or did we forget?

### Verification protocol

After all other audits complete (stage 26 of the pipeline):

1. Read the full audit trail of the ticket
2. Read referenced ADRs from `.studio/knowledge-base/architectural-decision-records/`
3. Read referenced DEF files from `.studio/deferred/`
4. For each pair of related entries: check for contradiction
5. For contradictions found: identify which is the truth, request the other be corrected

### Output: Consistency Cross-Check Report
```markdown
# Consistency Cross-Check — TKT-NNN

## Cross-role contradictions checked
- API Verification Specialist + Plugin Design Lead alignment: ✓
- Honesty Auditor + final code: ✓
- Edge Case Hunter findings + QA test plan: ✓

## Cross-phase contradictions checked
- Phase 1.B feasibility claims vs Phase 1.F implementation: ✓
- Phase 1.C architecture vs Phase 1.F as built: ✓
- Phase 1.D task breakdown vs sub-tasks completed: ✓

## Cross-file contradictions checked
- README claims vs code reality: ✓
- ADR-007 (use parse_property) vs code (uses parse_property): ✓
- plugin.cfg version vs CHANGELOG: ✓

## Cross-ticket contradictions checked
- TKT-005 ADR-003 (no Engine.is_editor_hint in domain code): ✓ honored
- TKT-007 ADR-005 (use EditorUndoRedoManager): ✓ honored

## Verdict
PASS — 0 contradictions found across the audit trail.
```

---

## The full pipeline script

`scripts/full-pipeline.sh` is the orchestration. It runs every script in order and stops at the first FAIL.

The script doesn't replace the human roles. It runs the *automatable* parts. The non-automatable parts (Clean Code Officer's qualitative judgment, Adversarial Hunt, ARB deliberation) happen separately, with their results captured into the audit trail. The script then reads the audit trail to verify these happened.

---

## Continuous Consistency mode

In addition to the per-ticket pipeline, Consistency Auditor runs in a **continuous mode** during Phase 1.F: every audit trail entry triggers a quick scan against the prior entries in the same ticket. This catches contradictions as they emerge, rather than at the end when fixing is expensive.

Example: in Phase 1.F.3, Tools Engineer logs "implemented commit_value using approach X." Continuous Consistency notes: "Phase 1.C committed to approach Y; this is a deviation." Raises immediate blocker; engineer either:
- Reverts to approach Y (architecture stands)
- Opens Phase 1.C amendment (architecture is amended)

This is the protocol's defense against silent drift.

---

## The unified pipeline script structure

```bash
#!/usr/bin/env bash
# full-pipeline.sh — runs the complete studio audit pipeline

set -uo pipefail

PLUGIN_DIR="${1:-addons/<your_plugin>}"

STAGES=(
    "1: Environment verification"
    "2: Setup integrity"
    "3: File integrity"
    "4: Parse check (godot --check-only)"
    "5: gdformat --check"
    "6: gdlint"
    "7: plugin.cfg conformance"
    "8: Editor smoke test"
    "9: Phase gate audit (Process Auditor)"
    "10: API verification scan"
    "11: Cross-impact scan"
    "12: Semantic dependency walk"
    "13: Forward wiring audit"
    "14: Reverse wiring audit"
    "15: Dead code scan"
    "16: Orphan reference scan"
    "17: Defect pattern walk"
    "18: Concurrency hunt"
    "19: State corruption hunt"
    "20: Adversarial hunt (XL only)"
    "21: Clean Code review"
    "22: Spaghetti scan"
    "23: Architectural quality audit"
    "24: 3-alternative documentation"
    "25: Trade-off matrix"
    "26: Consistency cross-check"
    "27: Documentation freshness"
    "28: Deferred items tracked"
    "29: Honesty Audit"
    "30: Final sign-off"
)

# (see scripts/full-pipeline.sh for actual implementation)
```

Each stage has:
- A clear owner role
- A verification mechanism (script-runnable, or role-judged)
- A PASS / FAIL / SKIP / N/A status
- Audit trail logging

---

## Skipping stages

Not every ticket runs every stage. Skip rules:

| Stage | When skippable |
|-------|----------------|
| 20 (Adversarial Hunt) | Skip on M and L tickets unless sensitive area |
| 24 (3 alternatives) | Skip on M and below — protocol applies to L/XL only |
| 25 (Trade-off matrix) | Same as 24 |
| 8 (Editor smoke test) | Skip if no project.godot in working dir |

Skips are explicit in the audit trail: `STATUS: SKIP — reason: M ticket, Adversarial Hunt not mandatory`. Skipped stages don't fail the pipeline, but they are visible.

---

## Manual stages

Some stages cannot be fully automated. They require role judgment:

- Stage 21 (Clean Code review) — Clean Code Officer reads files; judgment is qualitative
- Stage 23 (Architectural quality) — Architectural Quality Auditor walks call graph and lifecycle
- Stage 20 (Adversarial Hunt) — humans-as-roles attacking together

For these, the script doesn't perform the check — it verifies the check **was performed** by checking for the corresponding audit trail entry. If the entry is missing: FAIL with "stage not run; convene the role."

This makes the pipeline both an executor and an auditor of execution.

---

## Pipeline failure recovery

When a stage FAILs, the pipeline halts. Recovery:

1. The failing stage's owner role is summoned
2. They address the issue (write code, defer with DEF, justify and override)
3. Audit trail entry logged with resolution
4. Pipeline re-runs from the failing stage (or from start if upstream changes happened)
5. Continues until all stages pass or until override is signed

If the same stage fails 3+ times: this is a signal of deeper issues. The Tech Director intervenes. Possible causes:
- Ticket scope is wrong (return to Phase 1.A)
- Role assignment is wrong (different specialist needed)
- The check itself is calibrated wrong (Calibration Committee reviews the check criteria)

---

## Pipeline as documentation

The pipeline report is permanent — it's part of the ticket's audit trail. Future investigations can read it and understand exactly what was verified and what wasn't.

Six months from now, when the user asks "did we ever check X?" — the pipeline report for the relevant ticket answers definitively.

---

## What "tam otomasyon" means

The user asked for full automation. This is what it means in the studio:

- **Automated**: parse checks, lint, format, plugin.cfg conformance, dead code, orphan refs, smoke tests, cross-impact scans, wiring audits
- **Semi-automated** (script supports the role but role provides judgment): defect pattern walk, semantic dependency walk, concurrency/state hunts
- **Manual** (script verifies role's work was done): Clean Code review, architectural audit, Adversarial Hunt, sign-off

The full pipeline runs everything that can be run automatically, then verifies the manual parts happened. The result is a single PASS/FAIL signal for the whole ticket — that's the "tam otomasyon" outcome.

---

## When the pipeline is broken

If the pipeline itself has bugs (a script returns wrong results, a role's required entry format is broken), this is a P0 incident — the studio's safety net is compromised.

Incident Commander coordinates. Hot-fix Engineer patches the pipeline. Postmortem is mandatory. The pipeline reports for tickets closed during the broken-pipeline window are re-validated manually.

---

## Why this is the last v2.0 piece

Faz 1-7 added rules, roles, and protocols. Faz 8 makes them enforceable as a unit. Without Faz 8, the studio relies on individual roles remembering to run their checks. With Faz 8, the pipeline guarantees nothing is missed.

The studio's commitment after v2.0: every ticket has a complete pipeline report in its audit trail. No closure without a clean pipeline. No exceptions without explicit override + permanent record.

This is the final discipline that makes the studio actually AAA — not just by design, but by enforcement.
