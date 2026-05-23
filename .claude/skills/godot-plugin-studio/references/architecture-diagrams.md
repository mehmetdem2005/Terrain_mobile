# Studio Architecture Diagrams

ASCII diagrams of the studio's structure, ticket flow, and phase pipeline. These are reference visualizations for quick orientation when the prose feels overwhelming.

---

## Diagram 1: Studio organizational hierarchy

```
                            ┌──────────────────────────┐
                            │      USER (the human)    │
                            │   Interface = chat msgs  │
                            └────────────┬─────────────┘
                                         │
                                         │ requests
                                         ▼
                            ┌──────────────────────────┐
                            │       STUDIO HEAD        │
                            │  ┌────────────────────┐  │
                            │  │ Final sign-off (XL)│  │
                            │  └────────────────────┘  │
                            └────────────┬─────────────┘
                                         │
                                         ▼
                            ┌──────────────────────────┐
                            │     TECH DIRECTOR        │
                            │  - Ticket triage         │
                            │  - Mode selection        │
                            │  - L-tier sign-off       │
                            │  - Role activation       │
                            └────────────┬─────────────┘
                                         │
              ┌──────────┬───────────────┼───────────────┬──────────┐
              ▼          ▼               ▼               ▼          ▼
       ┌──────────┐ ┌──────────┐ ┌──────────────┐ ┌──────────┐ ┌────────┐
       │ Producer │ │ Plugin   │ │  Tools Lead  │ │ ARB      │ │ R&D    │
       │          │ │ Design   │ │              │ │ (3 seats)│ │ Eng.   │
       │ ticket   │ │ Lead     │ │ leads tools  │ │          │ │        │
       │ flow     │ │          │ │ engineering  │ │ design   │ │ spikes │
       └──────────┘ └──────────┘ └──────┬───────┘ │ approval │ └────────┘
                                        │         └──────────┘
                            ┌───────────┼───────────┐
                            ▼           ▼           ▼
                     ┌──────────┐ ┌─────────┐ ┌──────────────┐
                     │Inspector │ │Dock     │ │ UndoRedo     │
                     │Specialist│ │Specialist│ │ Specialist  │
                     └──────────┘ └─────────┘ └──────────────┘
                          (...and many more domain specialists)


  CROSS-CUTTING SUPERVISORS (always active, can interject any ticket):
  ┌─────────────────┐  ┌──────────────────┐  ┌────────────────────┐
  │ Honesty Auditor │  │Quality Gate Officer│  │ Consistency Auditor│
  └─────────────────┘  └──────────────────┘  └────────────────────┘
  ┌─────────────────┐  ┌──────────────────┐  ┌────────────────────┐
  │ Devil's Advocate│  │ Edge Case Hunter │  │ Risk Officer       │
  └─────────────────┘  └──────────────────┘  └────────────────────┘
  ┌─────────────────┐  ┌──────────────────┐  ┌────────────────────┐
  │ Polish Lead     │  │ Audit Trail Off. │  │ End-User Advocate  │
  └─────────────────┘  └──────────────────┘  └────────────────────┘


  v2.0 PROTOCOL ROLES (activated by Phase 1.E onward):
  ┌──────────────────────────┐  ┌──────────────────────────┐
  │ Architecture Veto Officer│  │ Architectural Debt Aud.  │
  └──────────────────────────┘  └──────────────────────────┘
  ┌──────────────────────────┐  ┌──────────────────────────┐
  │ Semantic Dependency Eng. │  │ Impact Analysis Engineer │
  └──────────────────────────┘  └──────────────────────────┘
  ┌──────────────────────────┐  ┌──────────────────────────┐
  │ Integration Engineer     │  │ Dead Code Hunter         │
  └──────────────────────────┘  └──────────────────────────┘
  ┌──────────────────────────┐  ┌──────────────────────────┐
  │ Bug Hunter Lead          │  │ + 3 Bug Specialists      │
  └──────────────────────────┘  └──────────────────────────┘
  ┌──────────────────────────┐  ┌──────────────────────────┐
  │ Clean Code Officer       │  │ Arch. Quality Auditor    │
  └──────────────────────────┘  └──────────────────────────┘
  ┌──────────────────────────┐  ┌──────────────────────────┐
  │ Innovation Scout         │  │ Trade-off Analyst        │
  └──────────────────────────┘  └──────────────────────────┘
  ┌──────────────────────────┐
  │ Pipeline Orchestrator    │
  └──────────────────────────┘
```

---

## Diagram 2: Ticket lifecycle (S/M tickets — collapsed)

```
   ┌──────────────┐
   │  USER msg    │
   └──────┬───────┘
          │
          ▼
   ┌──────────────────┐      ┌─────────────────┐
   │ Tech Director    │─────▶│ Roles activated │
   │ TRIAGE           │      │ (scaled to size)│
   └──────┬───────────┘      └─────────────────┘
          │
          ▼
   ┌──────────────────┐
   │  1.A Understand  │  (intent doc — even for S, internal note)
   └──────┬───────────┘
          │
          ▼
   ┌──────────────────┐
   │  Verify APIs     │  (1.B compressed for S/M)
   └──────┬───────────┘
          │
          ▼
   ┌──────────────────┐
   │  Implement       │  (1.F)
   └──────┬───────────┘
          │
          ▼
   ┌──────────────────┐
   │  Quality Gate    │  (Lite or Standard mode pipeline)
   └──────┬───────────┘
          │
          ▼
   ┌──────────────────┐
   │  Honesty Audit   │
   └──────┬───────────┘
          │
          ▼
   ┌──────────────────┐
   │  SIGN-OFF        │  (Quality Gate Officer for S; Tech Director for M)
   └──────────────────┘
```

---

## Diagram 3: Ticket lifecycle (L/XL — full 7-phase)

```
                    ┌─────────────┐
                    │  USER msg   │
                    └──────┬──────┘
                           │
                           ▼
                    ┌─────────────┐
                    │   TRIAGE    │ ── Tech Director
                    └──────┬──────┘
                           │
                           ▼
        ┌────────────────────────────────────┐
        │       Phase 1.A: Understanding     │
        │   Producer + Tech Director         │
        │   Output: intent-doc.md            │
        └─────────────┬──────────────────────┘
                      │   PASS?
                      ▼
        ┌────────────────────────────────────┐
        │       Phase 1.B: Discovery         │
        │   Feasibility + API Verify + R&D   │
        │   Output: feasibility-doc.md       │
        └─────────────┬──────────────────────┘
                      │   FEASIBLE?
                      ▼
        ┌────────────────────────────────────┐
        │       Phase 1.C: Architecture      │
        │   Plugin Design Lead + ARB         │
        │   + Innovation Scout (3 alts)      │
        │   + Trade-off Analyst (matrix)     │
        │   Output: architecture-doc.md      │
        │           + ADR(s)                 │
        └─────────────┬──────────────────────┘
                      │
                      ▼
        ┌────────────────────────────────────┐
        │       Phase 1.D: Planning          │
        │   Producer + Tools Lead + DoD      │
        │   + Manifesto Folder Check         │
        │   Output: task-breakdown.md        │
        └─────────────┬──────────────────────┘
                      │
                      ▼
        ╔════════════════════════════════════╗
        ║   Phase 1.E: ARCHITECTURE GATE     ║ ── hardest stop in studio
        ║   Architecture Veto Officer        ║
        ║   8-dimension evaluation           ║
        ║   PASS → 1.F                       ║
        ║   FAIL → back to 1.C               ║
        ╚═════════════╤══════════════════════╝
                      │   PASS
                      ▼
        ┌────────────────────────────────────┐
        │       Phase 1.F: Execution         │
        │   Tools + Engine Engineering       │
        │   Sub-task by sub-task             │
        │   wire-as-you-build (Faz 4)        │
        │   Continuous Consistency monitor   │
        └─────────────┬──────────────────────┘
                      │
                      ▼
        ┌────────────────────────────────────┐
        │       Phase 1.G: Integration       │
        │   Multi-role parallel pass:        │
        │   • Semantic Dependency walk       │
        │   • Impact Analysis scan           │
        │   • Forward + Reverse wiring       │
        │   • Dead Code + Orphan Ref         │
        │   • Defect Pattern walk (64)       │
        │   • Bug Hunter cohort + Adv.Hunt   │
        │   • Clean Code review              │
        │   • Architectural Quality audit    │
        │   • Consistency cross-check        │
        │   Output: integration-report.md    │
        └─────────────┬──────────────────────┘
                      │
                      ▼
        ┌────────────────────────────────────┐
        │   Pipeline Orchestrator runs       │
        │   scripts/full-pipeline.sh         │
        │   30 stages PASS or appropriate    │
        │   SKIP                             │
        └─────────────┬──────────────────────┘
                      │
                      ▼
        ┌────────────────────────────────────┐
        │   Honesty Audit (final)            │
        └─────────────┬──────────────────────┘
                      │
                      ▼
        ┌────────────────────────────────────┐
        │   SIGN-OFF                         │
        │   L: Tech Director                 │
        │   XL: Studio Head                  │
        └────────────────────────────────────┘
```

---

## Diagram 4: Phase 1.G integration — what runs in parallel

```
                 ┌──────────────────────────┐
                 │   Phase 1.F just closed  │
                 └────────────┬─────────────┘
                              │
              ┌───────────────┼───────────────┐
              │               │               │
              ▼               ▼               ▼
    ┌──────────────────┐ ┌──────────┐ ┌────────────────┐
    │ Semantic Dep.    │ │ Impact   │ │ Integration    │
    │ Engineer walks   │ │ Analysis │ │ Engineer wires │
    │ 100+ catalog     │ │ runs     │ │ audit          │
    └──────────┬───────┘ │ grep     │ └────────┬───────┘
               │         │ scans    │          │
               │         └─────┬────┘          │
               │               │               │
               ▼               ▼               ▼
              ┌──────────────────────────────────┐
              │     Findings consolidate         │
              │     into integration-report.md   │
              └────────────────┬─────────────────┘
                               │
                               ▼
              ┌──────────────────────────────────┐
              │ Bug Hunter Lead convenes hunt    │
              │  • Defect Pattern walks catalog  │
              │  • Concurrency Specialist        │
              │  • State Corruption Specialist   │
              │  • (XL only) Adversarial Hunt    │
              └────────────────┬─────────────────┘
                               │
                               ▼
              ┌──────────────────────────────────┐
              │ Clean Code Officer reviews files │
              │ Architectural Quality Auditor    │
              │ checks call graph + lifecycle    │
              └────────────────┬─────────────────┘
                               │
                               ▼
              ┌──────────────────────────────────┐
              │ Consistency Auditor cross-check  │
              │ across audit trail               │
              └────────────────┬─────────────────┘
                               │
                               ▼
              ┌──────────────────────────────────┐
              │ Pipeline Orchestrator runs       │
              │ full-pipeline.sh — unified gate  │
              └────────────────┬─────────────────┘
                               │
                            PASS or
                            FAIL?
```

---

## Diagram 5: Manifesto invariants layered with spaghetti catalog

```
┌──────────────────────────────────────────────────────────┐
│            CLEAN ARCHITECTURE MANIFESTO                  │
│             (the binding doctrine)                       │
├──────────────────────────────────────────────────────────┤
│  Invariant 1: one system  = one responsibility           │
│  Invariant 2: one file    = one clear job                │
│  Invariant 3: one function= one operation                │
│  Invariant 4: systems communicate by signals/events      │
│  Invariant 5: configuration is not hardcoded             │
│                                                          │
│  + Standard folder template                              │
│  + "Doesn't fall apart when it grows" test               │
└──────────────────────┬───────────────────────────────────┘
                       │
                       │ violations look like patterns from:
                       ▼
┌──────────────────────────────────────────────────────────┐
│            SPAGHETTI PATTERN CATALOG                     │
│            (what to avoid; 20+ patterns)                 │
├──────────────────────────────────────────────────────────┤
│  Tier 1 (blockers):                                      │
│   S-001 God Module       S-002 Lying Name                │
│   S-003 Wide Environment S-004 Manager God Object        │
│   S-005 Tangled Function S-006 Forever Temporary         │
│                                                          │
│  Tier 2 (smells):                                        │
│   S-007 Speculative Gen. S-008 Hidden State Machine      │
│   S-009 Config Cascade   S-010 Back-Reference            │
│   S-011 Stringly-Typed   S-012 Reaching Into             │
│   S-013 Boolean Trap     S-014 Magic Cluster             │
│   S-015 Comment Lying                                    │
│                                                          │
│  Tier 3 (style smells): S-016 to S-020                   │
│  Tier 4 (architectural): A-001 to A-008                  │
└──────────────────────────────────────────────────────────┘
```

---

## Diagram 6: The two-layer dependency detection

```
   "If I rename / change / add X, what else is affected?"

   ┌────────────────────────────────────────────────────┐
   │  LAYER 1: Syntactic (Impact Analysis Engineer)     │
   │  Tool: grep, cross-impact-scan.sh                  │
   │                                                    │
   │  Catches:                                          │
   │   • Renamed function → all callers                 │
   │   • Property type change → all assignments         │
   │   • File moved → all preload paths                 │
   │   • Class renamed → all extends, is, new() calls   │
   │                                                    │
   │  Speed: fast (seconds to minutes)                  │
   │  Misses: anything not in code text                 │
   └────────────────┬───────────────────────────────────┘
                    │
                    │ insufficient alone
                    ▼
   ┌────────────────────────────────────────────────────┐
   │  LAYER 2: Semantic (Semantic Dependency Engineer)  │
   │  Tool: 100+ rule catalog, 7-question audit         │
   │                                                    │
   │  Catches:                                          │
   │   • Added diff texture → check normal/roughness/AO │
   │   • Added @export → consider @export_group context │
   │   • Added signal → emitter + listener pair         │
   │   • Added state → invalidate caches that depend    │
   │   • Lifecycle change → cleanup symmetry            │
   │   • UndoRedo action → undo/redo symmetric          │
   │   • Mobile target → Android editor compat          │
   │   • Save format → migration path                   │
   │                                                    │
   │  Speed: 10-20 minutes for L ticket                 │
   │  Misses: nothing if catalog is current             │
   └────────────────────────────────────────────────────┘

   Both layers run in Phase 1.G. Findings consolidate.
```

---

## Diagram 7: Mode-vs-Pipeline-stages relationship

```
                  ┌──────────────────────────────────────────┐
                  │   30 stages total in full-pipeline.sh    │
                  └──────────────────────────────────────────┘

   LITE (S tickets):           STANDARD (M, most L):       FULL (XL, releases):
   8 stages, <5 min            20 stages, 15-30 min         30 stages, 1-2 hours
   ┌──────────┐                ┌──────────┐                 ┌──────────┐
   │ stage 1  │ env            │ stage 1  │ ─┐              │ stage 1  │ ─┐
   │ stage 2  │ setup          │ stage 2  │  │              │ stage 2  │  │
   │ stage 3  │ files          │ stage 3  │  │              │ stage 3  │  │
   │ stage 4  │ parse          │ stage 4  │  │              │ stage 4  │  │
   │ stage 5  │ format         │ stage 5  │  │              │ stage 5  │  │
   │ stage 6  │ lint           │ stage 6  │  │              │ stage 6  │  │
   │ stage 7  │ plugin.cfg     │ stage 7  │  │              │ stage 7  │  │
   │ stage 29 │ Honesty Audit  │ stage 8  │  │              │ stage 8  │  │
   └──────────┘                │ stage 9  │  │              │ stage 9  │  │
                               │ ... 11   │  │ (Lite +      │ stage 10 │  │
                               │ stage 12 │  │  semantic +  │ ... etc  │  │
                               │ stage 13 │  │  wiring +    │ stage 30 │  │
                               │ stage 14 │  │  dead code + │          │  │
                               │ stage 15 │  │  patterns +  │ (Standard│  │
                               │ stage 17 │  │  clean code) │  +       │  │
                               │ stage 18 │  │              │ Adversar.│  │
                               │ stage 19 │  │              │ Hunt +   │  │
                               │ stage 21 │  │              │ 3-alts + │  │
                               │ stage 22 │  │              │ full     │  │
                               │ stage 26 │  │              │ matrix + │  │
                               │ stage 28 │  │              │ ALL)     │  │
                               │ stage 29 │ ─┘              │          │  │
                               └──────────┘                 └──────────┘  │

   Triage criteria → see references/cost-aware-execution.md
```

---

## Diagram 8: Where each major concept lives

```
   ASKING ABOUT...           READ...
   ─────────────────────────────────────────────────────────────
   ticket flow      ──────▶  coordination-protocol.md
   sign-off rules   ──────▶  quality-gates.md
   role list        ──────▶  01-executive-production.md to 14-community-support.md
   the 7 phases     ──────▶  multi-phase-execution-protocol.md
   architecture     ──────▶  architectural-veto-protocol.md
                             clean-architecture-manifesto.md
                             architectural-quality-audit.md
   dependencies     ──────▶  semantic-dependency-engine.md (semantic)
                             impact-analysis-protocol.md (syntactic)
   wiring & dead    ──────▶  integration-enforcement-protocol.md
   bugs             ──────▶  bug-hunting-protocol.md
                             godot-4.6.2-defect-catalog.md
   clean code       ──────▶  architectural-quality-audit.md
                             spaghetti-pattern-catalog.md
                             clean-architecture-manifesto.md
   alternatives     ──────▶  innovation-engine.md
   automation       ──────▶  automation-pipeline.md
   nothing lost     ──────▶  deferred-work-tracker.md
   pipeline modes   ──────▶  cost-aware-execution.md
   real example     ──────▶  cookbook-real-plugin-walkthrough.md
   navigation       ──────▶  skill-navigation-guide.md
   ─────────────────────────────────────────────────────────────
```

---

End of diagrams. These are reference visuals; the prose files are authoritative for detail.
