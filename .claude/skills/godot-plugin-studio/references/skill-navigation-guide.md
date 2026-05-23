# Skill Navigation Guide

This skill has grown large. 60+ files. Reading everything for every ticket is wasteful. This guide tells you **what to read when**, organized by your immediate situation.

The studio's principle: **load context just-in-time.** Don't pre-load files you won't need. Don't skip files you do.

---

## Decision tree — what do you read first?

### "I just got a new ticket."
1. Read `SKILL.md` (the charter) if you haven't this session
2. **Determine domain:** is this a plugin ticket or a game ticket? See triage rules below.
3. Read the relevant department file based on ticket type:
   - **Plugin domain:**
     - Plugin entry / lifecycle issue → `references/03-tools-engineering.md`
     - Engine subsystem (audio, physics, render) → `references/04-engine-engineering.md`
     - Performance question → `references/05-performance.md`
     - QA / testing → `references/06-qa-testing.md`
   - **Game domain (v2.1):**
     - Any game ticket → `references/15-game-dev-departments.md`
     - Plus `references/game-development-protocols.md`
     - Plus `references/game-defect-catalog.md` for defect walks
4. Read `references/coordination-protocol.md` for ticket flow
5. Read `references/quality-gates.md` for sign-off criteria at your ticket's size (includes G-1..G-8 for game tickets)

That's the minimum. Stop here for S/M tickets.

### Domain triage — plugin or game?

| Signal | Domain |
|--------|--------|
| "Build a Godot plugin for..." | Plugin |
| "EditorPlugin / inspector / dock" | Plugin |
| "Editor tool that..." | Plugin |
| "Add to Asset Library" | Plugin |
| "Build a Godot game where..." | Game |
| "Player controller / state machine" | Game |
| "Save system / save corruption" | Game |
| "Scene transition / loading screen" | Game |
| "Game stutters on mobile" | Game |
| "Multiplayer state desync" | Game |
| "Game feel / responsiveness" | Game |
| "Make my plugin not load on Android" | Plugin |
| "My game won't run on Android" | Game |
| Ambiguous | Ask one clarifying question before proceeding |

### "This is an L or XL ticket."
Add to the above:
5. Read `references/multi-phase-execution-protocol.md` — the 7 phases
6. Read `references/phase-gate-checklist.md` — gate criteria
7. Read `references/clean-architecture-manifesto.md` — the binding invariants
8. Reference `references/innovation-engine.md` at Phase 1.C for the 3-alternative rule

### "I'm at a specific phase right now."

| Phase | Required reading |
|-------|-----------------|
| 1.A Understanding | (nothing extra; intent capture is roles + protocol) |
| 1.B Discovery | `references/godot-4.6.2-api-pitfalls.md`, `references/godot-4.6.2-gdscript-rules.md` |
| 1.C Architecture | `references/innovation-engine.md`, `references/clean-architecture-manifesto.md` |
| 1.D Planning | `references/clean-architecture-manifesto.md` (folder template), `references/phase-gate-checklist.md` (sections 1.D.9-12) |
| 1.E Architecture Gate | `references/architectural-veto-protocol.md` |
| 1.F Execution | `references/integration-enforcement-protocol.md` (wire-as-you-build) |
| 1.G Integration | `references/semantic-dependency-engine.md`, `references/impact-analysis-protocol.md`, `references/integration-enforcement-protocol.md`, `references/bug-hunting-protocol.md`, `references/godot-4.6.2-defect-catalog.md`, `references/architectural-quality-audit.md`, `references/spaghetti-pattern-catalog.md`, `references/automation-pipeline.md` |

### "I have a specific concern right now."

| Concern | Read |
|---------|------|
| Is this API real in 4.6.2? | `references/godot-4.6.2-api-pitfalls.md`, then verify against `~/godot-api-reference/` |
| Will this work on Android editor? | `references/godot-4.6.2-mobile.md` |
| Does this code feel spaghetti? | `references/spaghetti-pattern-catalog.md` + `references/clean-architecture-manifesto.md` |
| Am I forgetting a domino effect? | `references/semantic-dependency-engine.md` (walk relevant categories) |
| Did I leave dead code? | `scripts/dead-code-scan.sh` + `references/integration-enforcement-protocol.md` |
| Am I missing a known bug pattern? | `references/godot-4.6.2-defect-catalog.md` (64 patterns) |
| Did I lose track of something deferred? | `.studio/deferred/` directory + `references/deferred-work-tracker.md` |
| User asks "what's pending?" | `references/deferred-work-tracker.md` (inventory query) |
| Need to wire a new specialist role? | `references/role-instantiation-protocol.md` |

### "I'm asked to do a full audit / final check."
Read in this order:
1. `references/automation-pipeline.md` (the orchestration)
2. `scripts/full-pipeline.sh` (the runnable check)
3. Specific gate references as failures surface

---

## File index — what each file is for

### Charter
- **`SKILL.md`** — entry point; operating principles; org chart; activation rules

### Department role definitions (14 files)
Read only the relevant ones per ticket. Each defines roles + their charters + activation triggers.
- **`01-executive-production.md`** — Studio Head, Tech Director, Producer, Triage Officer
- **`02-tech-leadership.md`** — Principal Engineer, Plugin Design Lead, ARB, R&D Engineer
- **`03-tools-engineering.md`** — Tools Lead + specialists (inspector, dock, importer, signal, undo/redo, etc.)
- **`04-engine-engineering.md`** — Engine specialists (renderer, physics, audio, animation, networking)
- **`05-performance.md`** — Performance Lead + profiling specialists
- **`06-qa-testing.md`** — QA Lead, Test Engineer, Scenario Designer, Reproduction Engineer
- **`07-security-stability.md`** — Security Reviewer, Crash Auditor, Stability Engineer
- **`08-documentation-dx.md`** — Technical Writer, Tutorial Writer, Examples Maintainer
- **`09-cross-cutting-supervisors.md`** — Honesty Auditor, Quality Gate Officer, Consistency Auditor, Devil's Advocate, Edge Case Hunter, etc.
- **`10-preproduction-rd.md`** — Feasibility Analyst, Prior Art Researcher, Spike Coordinator
- **`11-release-compliance.md`** — Asset Library Officer, License Reviewer, Release Manager
- **`12-performance-development.md`** — Performance Analytics Engineer (per-role scoring)
- **`13-incident-response.md`** — Incident Commander, Hot-fix Engineer, Postmortem Writer
- **`14-community-support.md`** — Support Lead, Community Liaison

### Coordination protocols (3 files, always relevant)
- **`coordination-protocol.md`** — ticket state machine, audit trail format, escalation
- **`quality-gates.md`** — sign-off criteria per ticket size (S/M/L/XL/U-tier)
- **`role-instantiation-protocol.md`** — how to wake up a new specialist role mid-ticket

### v2.0 execution protocols (8 files, for L/XL tickets)
- **`multi-phase-execution-protocol.md`** — the 7 phases
- **`phase-gate-checklist.md`** — exact PASS/FAIL criteria per phase
- **`architectural-veto-protocol.md`** — Veto Officer + Debt Auditor roles
- **`semantic-dependency-engine.md`** — 100+ pattern catalog for domino effects
- **`impact-analysis-protocol.md`** — grep-based syntactic dependency scan
- **`integration-enforcement-protocol.md`** — wire-as-you-build discipline
- **`deferred-work-tracker.md`** — DEF-NNN system, nothing forgotten
- **`bug-hunting-protocol.md`** — offensive bug-hunting cohort
- **`automation-pipeline.md`** — full pipeline orchestration

### v2.0 quality protocols (3 files)
- **`architectural-quality-audit.md`** — Clean Code Officer + qualitative criteria
- **`spaghetti-pattern-catalog.md`** — 20+ anti-patterns with examples
- **`clean-architecture-manifesto.md`** — binding doctrine + folder template + invariants

### v2.0 innovation (1 file)
- **`innovation-engine.md`** — 3-alternative rule + Innovation Scout + Trade-off Analyst

### Domain knowledge (4 files, reference as needed)
- **`godot-4.6.2-api-pitfalls.md`** — known API gotchas in 4.6.2
- **`godot-4.6.2-gdscript-rules.md`** — GDScript syntax rules and idioms
- **`godot-4.6.2-mobile.md`** — Forward Mobile renderer + Android editor constraints
- **`godot-4.6.2-defect-catalog.md`** — 64 recognized defect patterns

### Scripts (8 files in `scripts/`)
Run these from project root.
- **`setup-godot.sh`** — environment bootstrap
- **`ci-checks.sh`** — minimal parse + lint + smoke check
- **`cross-impact-scan.sh`** — symbol-level grep for renames
- **`dead-code-scan.sh`** — orphan functions, unused files, broken preloads
- **`wiring-audit.sh`** — forward wiring (public symbol → caller)
- **`reverse-wiring-audit.sh`** — reverse wiring (file → referenced from)
- **`consistency-cross-check.sh`** — audit trail contradiction scan
- **`full-pipeline.sh`** — all 30 stages in order

---

## Reading budgets per ticket size

How much you should read scales with ticket size. Reading the wrong amount is its own failure mode — too little misses risks, too much wastes context.

### S (small) ticket — under 1 hour of work
**Read:** `SKILL.md`, `coordination-protocol.md`, `quality-gates.md` (S section).
**Skip:** everything in v2.0 protocols. S tickets don't need them.
**Total reading time:** ~5 minutes.

### M (medium) ticket — 1 day of work
**Read:** S list + relevant department files + `multi-phase-execution-protocol.md` (collapsed M section) + `clean-architecture-manifesto.md` (skim).
**Skip:** XL-only protocols (Adversarial Hunt, 3-alternative, full Bug Hunting).
**Total reading time:** ~15 minutes.

### L (large) ticket — days of work
**Read:** Everything in M + all v2.0 execution protocols + relevant defect/pattern catalogs.
**Skip:** XL-only (Adversarial Hunt is optional; 3-alt is required but lighter).
**Total reading time:** ~30 minutes (mostly skim of catalogs).

### XL (extra large) ticket — week+ of work
**Read:** Everything. All catalogs, all protocols. Adversarial Hunt mandatory.
**Total reading time:** ~45-60 minutes setup + ongoing reference during execution.

---

## Progressive disclosure pattern

When the studio is uncertain whether a deep dive is needed, the pattern is:

1. **Read the summary** (top sections of the file)
2. **Use it to triage** — is this scenario applicable to me?
3. **If yes:** read the full file
4. **If no:** move on

Most files have a "Why this exists" section near the top — that's enough to know whether the file applies.

---

## Cross-references — when to read alongside

Some files are best read together. The studio's recommended pairings:

- `clean-architecture-manifesto.md` + `spaghetti-pattern-catalog.md` — positive rules + what to avoid
- `semantic-dependency-engine.md` + `impact-analysis-protocol.md` — semantic + syntactic dependency
- `integration-enforcement-protocol.md` + `clean-architecture-manifesto.md` — wiring + structural cleanliness
- `bug-hunting-protocol.md` + `godot-4.6.2-defect-catalog.md` — bug hunting + the catalog being walked
- `architectural-veto-protocol.md` + `architectural-quality-audit.md` — design-time vs build-time architectural checks
- `multi-phase-execution-protocol.md` + `phase-gate-checklist.md` — the phases + their criteria

---

## "I just want the cheat sheet"

If you read only one file in this skill (which is not what we recommend), read `SKILL.md`. Everything else is referenced from there.

The studio's hottest hot-take in one screen:

```
The studio runs as ~80 roles coordinating through tickets, scaled to ticket
size. Every claim is verified before sign-off. Architecture is locked at
Phase 1.E before any code is written. Domino effects are tracked through
semantic + syntactic dependency layers. Bugs are hunted proactively across
64 known patterns. Code quality is measured qualitatively against five
binding invariants (one system = one responsibility, one file = one job,
one function = one operation, systems communicate by signals/events,
configuration not hardcoded). Nothing is deferred without a tracker entry.
A full pipeline of 30 stages runs at Phase 1.G; nothing ships without it.

The standard: code that doesn't fall apart when the project grows.
```

---

## When this guide is wrong

This guide reflects the studio's intended navigation. If you find it leads you to read the wrong files, that's a defect in this guide — report it. The Studio Knowledge Curator updates the guide based on real navigation failures, not on theoretical correctness.
