# Cookbook — A Real Plugin from Scratch

A walkthrough of how the studio actually executes a real plugin ticket. This is not theory; this is what the audit trail looks like, what each phase produces, what the conversations sound like.

The example: build a custom EditorInspectorPlugin that adds a vector field drawer for Vector3 properties tagged with `@export_custom(PROPERTY_HINT_VECTOR_FIELD)`. This is an L-tier ticket. Standard mode pipeline.

This walkthrough is intentionally long. Skim it the first time, return to it as a reference when you're in a similar phase.

---

## Ticket creation — TKT-001

User says: "I want a plugin where I can use `@export_custom(PROPERTY_HINT_VECTOR_FIELD, '')` on a Vector3 property and get a custom inspector drawer that shows X/Y/Z components plus a small 2D direction indicator."

### Triage (Tech Director)
- Size assessment: this is L. Touches plugin lifecycle, custom inspector plugin, custom drawer, and a hint system. Several files.
- Mode: Standard (no plugin.cfg lifecycle complications visible yet, no security, no persistence schema)
- Roles to activate: Plugin Design Lead, ARB (3 seats), Tools Lead, Inspector Specialist, Theme/UI Specialist, UndoRedo Specialist, Tutorial Writer, Honesty Auditor (always), Quality Gate Officer (always)
- v2.0 protocol roles: Architecture Veto Officer (Phase 1.E), Semantic Dependency Engineer (Phase 1.G), Integration Engineer (Phase 1.F/G), Dead Code Hunter (Phase 1.G), Clean Code Officer + Architectural Quality Auditor (Phase 1.G), Innovation Scout + Trade-off Analyst (Phase 1.C), Pipeline Orchestrator (Phase 1.G)

Ticket file `.studio/tickets/TKT-001.json` created.

---

## Phase 1.A — Understanding

**Producer + Tech Director joint:**

### `intent-doc.md` output

```markdown
# Intent — TKT-001

## What the user said (verbatim)
"I want a plugin where I can use @export_custom(PROPERTY_HINT_VECTOR_FIELD, '') 
on a Vector3 property and get a custom inspector drawer that shows X/Y/Z 
components plus a small 2D direction indicator."

## What they actually want (our interpretation)
An editor plugin that adds a custom inspector drawer for Vector3 properties 
when annotated with a specific hint. The drawer shows three numeric inputs 
(X, Y, Z) and a visual direction indicator (probably top-down 2D view of XZ).

## Hard requirements
- Plugin loads in editor
- @export_custom(PROPERTY_HINT_VECTOR_FIELD, '') on Vector3 properties is intercepted
- Drawer shows X, Y, Z numeric inputs
- Drawer shows a 2D direction indicator
- Editing values commits through UndoRedo (so user's undo works)
- Drawer respects editor theme

## Soft preferences
- (none stated)

## Out of scope
- Mobile/Android editor (will be evaluated but not a hard requirement)
- 3D viewport gizmo (separate feature; user did not request)
- Animation/tweening between values
- Multi-select editing (act on one Vector3 at a time)

## Unknowns to resolve in Phase 1.B
- Does PROPERTY_HINT_VECTOR_FIELD exist in Godot 4.6.2 as a built-in hint? 
  (we suspect NOT; we'd need to use PROPERTY_HINT_NONE with a custom hint string)
- What's the right way for EditorInspectorPlugin to filter by hint?
- Does the drawer need its own Control or can it embed in the inspector's flow?

## Confidence
HIGH — request is concrete; only API details need verification
```

User confirms interpretation. Phase 1.A passes.

---

## Phase 1.B — Discovery

**Feasibility Analyst + API Verification Specialist:**

### Feasibility doc

```markdown
# Feasibility — TKT-001

## Required capabilities verified
| Capability | Godot 4.6.2 status | Evidence |
|-----------|--------------------|----------|
| EditorInspectorPlugin | EXISTS | grep EditorInspectorPlugin.xml in ~/godot-api-reference/ |
| _parse_property callback | EXISTS | EditorInspectorPlugin.xml line 89 |
| @export_custom annotation | EXISTS | GDScript 4.x docs |
| PROPERTY_HINT_VECTOR_FIELD constant | DOES NOT EXIST | not found in @GlobalScope.xml |
| Custom hint strings via _parse_property | WORKS | _parse_property receives hint_string parameter |
| EditorUndoRedoManager | EXISTS | EditorUndoRedoManager.xml |
| EditorInterface.get_editor_theme() | EXISTS | EditorInterface.xml line 142 |

## Prior art
- Searched Asset Library for "vector field inspector" — 0 matches
- Searched GitHub for Godot 4.x custom Vector3 inspectors — found 3 patterns, 
  reviewed; none address the visual direction indicator requirement
- Conclusion: this is a new build; no fork target

## Spikes run
- Spike 1: confirm @export_custom hint string can be arbitrary (e.g., "VECTOR_FIELD")
  Result: yes. _parse_property(object, type, name, hint_type, hint_string, usage)
  receives hint_string verbatim. We define our own convention.

## Verdict
FEASIBLE WITH CAVEATS
- Caveat: PROPERTY_HINT_VECTOR_FIELD doesn't exist; we'll use 
  PROPERTY_HINT_NONE with hint_string="VECTOR_FIELD" as the convention
- Caveat: user originally asked for PROPERTY_HINT_VECTOR_FIELD — we'll need 
  to communicate the actual syntax in documentation
```

Tech Director routes back to user: "PROPERTY_HINT_VECTOR_FIELD isn't a built-in hint. Suggest using `@export_custom(PROPERTY_HINT_NONE, 'VECTOR_FIELD')` — same end result."

User confirms.

Phase 1.B passes.

---

## Phase 1.C — Architecture

**Plugin Design Lead + ARB + Innovation Scout + Trade-off Analyst:**

### Innovation Scout's research

Surveyed:
- Godot Asset Library (3 similar plugins, all simpler)
- Unity Inspector PropertyDrawer (decorator pattern)
- Unreal Details panel custom widgets
- Blender custom property panels

Brought back 4 conceptual approaches.

### Plugin Design Lead drafts 3 alternatives (per `innovation-engine.md`)

```markdown
# Architecture — TKT-001

## Solution chosen: Alternative A

## Alternatives considered

### Alternative A: Intercept-and-replace (conservative)
**Approach:** EditorInspectorPlugin intercepts Vector3 properties with hint_string=="VECTOR_FIELD". Returns true from _parse_property; replaces the default Vector3 editor with a custom Control containing three SpinBox inputs and a small Control subclass drawing the 2D direction indicator.

**Module structure:**
- plugin.gd: EditorPlugin entry, registers VectorFieldInspectorPlugin
- inspector.gd: EditorInspectorPlugin subclass
- drawer.gd: Custom Control with the layout
- direction_indicator.gd: Custom Control just for the 2D indicator

**Strengths:** Matches Godot inspector conventions; users find it where they expect.
**Weaknesses:** Limited space in inspector; 2D indicator must be small.

### Alternative B: Side-panel companion
**Approach:** Leave the default Vector3 editor untouched; add a Dock that appears when a Vector3 with VECTOR_FIELD hint is selected, showing a larger version.

**Strengths:** More screen space; richer UI.
**Weaknesses:** Discoverable problem (users don't know the panel exists); modal-ish behavior.

### Alternative C: 3D viewport gizmo
**Approach:** Detect VECTOR_FIELD properties in selection; draw an interactive gizmo in the 3D viewport.

**Strengths:** Direct spatial manipulation.
**Weaknesses:** Significant implementation cost; out of scope per intent doc.

## Trade-off matrix (Trade-off Analyst)
| Dimension | A | B | C |
|-----------|---|---|---|
| Maintainability | NEUTRAL | NEUTRAL | WORSE (viewport plugin complex) |
| Performance | BETTER (event-driven) | NEUTRAL | WORSE (per-frame gizmo) |
| Complexity | BETTER (~300 LOC est.) | NEUTRAL (~500 LOC) | WORSE (~1000 LOC) |
| Mobile compat | BETTER (inspector works) | NEUTRAL | WORSE |
| Implementation time | BETTER (2-3 days) | NEUTRAL (4-5 days) | WORSE (1+ weeks) |
| Risk | BETTER (familiar pattern) | NEUTRAL | WORSE |
| User experience | NEUTRAL | BETTER (more room) | BETTER (direct) |
| Extensibility | NEUTRAL | BETTER | NEUTRAL |

## Chosen: Alternative A
**Rationale:** A matches the user's stated scope (inspector drawer; user didn't ask for panel or gizmo). B is interesting but adds a discoverability problem. C is explicitly out-of-scope per Phase 1.A. A wins on 5 of 8 matrix dimensions; the dimensions where B/C win don't address requirements the user prioritized.

**Risks accepted:**
- 2D direction indicator will be small (~80px square area). If user feedback says it's too small, we revisit (deferred risk DEF-002 in tracker).
- Inspector visual real estate is constrained; if VECTOR_FIELD use grows, B may become preferable later.

## ADRs created
- ADR-001: Use PROPERTY_HINT_NONE with hint_string="VECTOR_FIELD" as the convention
- ADR-002: Custom Control hierarchy for drawer (vs single _draw override) — chose hierarchy for accessibility (focusable SpinBoxes)

## Module structure (per clean-architecture-manifesto)
addons/vector_field_inspector/
├── plugin.cfg
├── README.md
├── icon.png
├── core/
│   └── plugin.gd
├── inspector/
│   ├── inspector_plugin.gd
│   └── drawer.gd
├── ui/
│   └── direction_indicator.gd
└── domain/
    └── vector_field_math.gd        # any direction-vector math
```

ARB votes: 3/3 PASS. Phase 1.C passes.

---

## Phase 1.D — Planning

**Producer + Tools Lead + DoD Steward + Impact Analyzer + Manifesto Folder Check:**

### Task breakdown

```markdown
# Task Breakdown — TKT-001

## Sub-tasks (ordered)

### ST-01: Create plugin.cfg + icon
- Owner: Senior Tools Engineer
- Depends on: nothing
- Blocks: ST-02
- Files: plugin.cfg, icon.png
- Acceptance: plugin.cfg parses; all required fields present; icon is 16x16 PNG
- Phase coverage: 1.F

### ST-02: Create core/plugin.gd (EditorPlugin entry)
- Owner: Senior Tools Engineer
- Depends on: ST-01
- Blocks: ST-03
- Files: core/plugin.gd
- Acceptance: _enter_tree registers inspector_plugin; _exit_tree unregisters
- Phase coverage: 1.F

### ST-03: Create inspector/inspector_plugin.gd
- Owner: Inspector Specialist
- Depends on: ST-02
- Blocks: ST-04
- Files: inspector/inspector_plugin.gd
- Acceptance: _can_handle returns true for Object; _parse_property returns true for Vector3 + hint_string=="VECTOR_FIELD"; inserts drawer.gd instance via add_property_editor
- Phase coverage: 1.F

### ST-04: Create domain/vector_field_math.gd (pure logic)
- Owner: Tools Engineer
- Depends on: ST-02
- Blocks: ST-05
- Files: domain/vector_field_math.gd
- Acceptance: Pure functions (no Godot editor deps) for normalize, magnitude, angle_xz
- Phase coverage: 1.F (parallel with ST-03)

### ST-05: Create inspector/drawer.gd (3 SpinBox + indicator)
- Owner: Inspector Specialist + Theme/UI Specialist
- Depends on: ST-03, ST-04
- Blocks: ST-06
- Files: inspector/drawer.gd
- Acceptance: Drawer displays 3 SpinBox controls; commits to target object via EditorUndoRedoManager; respects editor theme colors
- Phase coverage: 1.F

### ST-06: Create ui/direction_indicator.gd (2D visual)
- Owner: Theme/UI Specialist
- Depends on: ST-05
- Blocks: ST-07
- Files: ui/direction_indicator.gd
- Acceptance: Draws unit circle + arrow from center showing XZ direction; updates on drawer value changes
- Phase coverage: 1.F

### ST-07: Wire integration + lifecycle test
- Owner: Integration Engineer
- Depends on: ST-06
- Blocks: ST-08
- Files: (verification only)
- Acceptance: Plugin enables, drawer renders for Vector3 with VECTOR_FIELD hint, edits commit through undo
- Phase coverage: 1.F.7 / 1.G

### ST-08: Write README
- Owner: Tutorial Writer
- Depends on: ST-07
- Blocks: (close)
- Files: README.md
- Acceptance: Installation, usage example with @export_custom syntax, undo/redo guarantee, theme respect noted
- Phase coverage: 1.F (parallel with 1.G integration)

## Execution order
- Phase 1.F.1 (blocking): ST-01 → ST-02
- Phase 1.F.2 (parallel): ST-03, ST-04
- Phase 1.F.3 (sequential after 1.F.2): ST-05
- Phase 1.F.4 (after ST-05): ST-06
- Phase 1.F.5 (after ST-06): ST-07
- Phase 1.F.6 (parallel with 1.F.5): ST-08

## Folder structure verification (manifesto Phase 1.D.9-12)
- 1.D.9: structure matches standard ✓
- 1.D.10: each file has one-phrase job (no helpers/utils) ✓
- 1.D.11: each system one-sentence responsibility ✓:
  - core: "plugin lifecycle"
  - inspector: "intercepts Vector3 properties with VECTOR_FIELD hint"
  - ui: "visual indicator rendering"
  - domain: "vector math, no editor deps"
- 1.D.12: cross-system comms documented:
  - plugin.gd → inspector_plugin.gd via add_inspector_plugin
  - inspector_plugin.gd → drawer.gd via add_property_editor
  - drawer.gd → vector_field_math via direct method calls (math is pure utility)
  - drawer.gd → direction_indicator via Control composition + signal
  - drawer.gd → target object via EditorUndoRedoManager (no direct mutation)
```

DoD Steward signs. Phase 1.D passes.

---

## Phase 1.E — Architecture Gate

**Architecture Veto Officer:**

### Per-dimension verdicts
- Module boundaries: SOLID — clean separation of concerns
- Coupling discipline: SOLID — drawer doesn't reach into inspector; direction_indicator is composed, not coupled
- Lifecycle completeness: SOLID — _enter_tree/_exit_tree symmetric
- Extension accommodation: SOLID — adding a new variant (e.g., color field) would touch ~2 modules
- Explainability: SOLID — design fits in <5min sketch
- Spaghetti indicators: NONE
- Over-engineering indicators: NONE — abstraction matches complexity
- Task breakdown fidelity: SOLID — 1.D matches 1.C exactly

### Verdict: PASS

Phase 1.E passes. Code can be written.

---

## Phase 1.F — Execution

The studio executes sub-tasks in the ordered sequence. Per `integration-enforcement-protocol.md`, each sub-task closes only with wiring verified.

### Audit trail excerpt (illustrative)

```json
{"timestamp": "...", "role": "Senior Tools Engineer", "action": "complete_subtask", 
 "subtask": "ST-01", "files": ["plugin.cfg", "icon.png"], "verification": "godot --headless --check-only confirms cfg parses; icon dimensions verified 16x16"}

{"timestamp": "...", "role": "Senior Tools Engineer", "action": "complete_subtask", 
 "subtask": "ST-02", "files": ["core/plugin.gd"], "verification": "plugin loads in editor; _enter_tree fires; _exit_tree symmetric (verified with reload cycle)"}

{"timestamp": "...", "role": "Inspector Specialist", "action": "complete_subtask", 
 "subtask": "ST-03", "files": ["inspector/inspector_plugin.gd"], 
 "verification": "instantiated from plugin.gd:18; add_inspector_plugin invoked; remove on exit"}

{"timestamp": "...", "role": "Tools Engineer", "action": "complete_subtask", 
 "subtask": "ST-04", "files": ["domain/vector_field_math.gd"], 
 "verification": "5 pure functions; unit-testable; no Engine.is_editor_hint calls"}
```

After ST-04: Continuous Consistency Auditor checks — no drift from Phase 1.C design. PASS.

[ST-05 through ST-08 continue similarly. Audit trail records each.]

Phase 1.F closes with all sub-tasks complete and audit trail intact.

---

## Phase 1.G — Integration

This is where the v2.0 protocols hit full force.

### Semantic dependency walk (Semantic Dependency Engineer)

The Engineer walks the catalog (`semantic-dependency-engine.md`) for each new concept:

**Concept C1: new EditorInspectorPlugin**
- A1 (add_*/remove_* symmetry): PASS — add at plugin.gd:18, remove at plugin.gd:31
- A2 (_enter_tree/_exit_tree): PASS — symmetric
- C1 (custom drawer for property): PASS — drawer commits via UndoRedo (verified)
- L1 (mutating action via UndoRedo): PASS — EditorUndoRedoManager.create_action used
- K1 (editor theme colors): PASS — direction_indicator pulls colors from EditorInterface theme
- K3 (focus mode): PASS — SpinBoxes are focusable; tab order: X → Y → Z → indicator
- Q1 (new public API for users): PASS — README documents @export_custom syntax

**Concept C2: VECTOR_FIELD hint string convention**
- Q1 (new public API): PASS — README documents the hint string
- J1 (persistence schema): N/A — no persistence

**Concept C3: direction_indicator custom Control**
- C1 (drawer for property): N/A — this is a sub-component
- K1 (theme colors): PASS
- K3 (focus mode): NOT FOCUSED — drawer-only navigation; documented in code comment

Verdict: PASS. All applicable catalog rules addressed.

### Forward wiring audit (Integration Engineer)
```
bash scripts/wiring-audit.sh addons/vector_field_inspector
> 0 orphan public functions
> 0 dead signals
> All signals have appropriate emitters and listeners
```

### Reverse wiring audit
```
bash scripts/reverse-wiring-audit.sh addons/vector_field_inspector
> 5 files scanned, all wired
> 0 orphan files
```

### Dead code scan
```
bash scripts/dead-code-scan.sh addons/vector_field_inspector
> 0 true dead code findings
```

### Defect pattern walk (Defect Pattern Specialist)
Walked all 64 patterns from `godot-4.6.2-defect-catalog.md`.

Findings:
- All A-category patterns (lifecycle): PASS
- B-category (signals): PASS — drawer's value_changed signal has documented public API status
- C-category (inspector): PASS — drawer commits via UndoRedo; refresh on object change handled
- D-category (resources): N/A — no Resource subclasses
- E-category (textures): N/A — no textures shipped
- F-category (shaders): N/A
- G-category (scene tree): N/A — plugin doesn't modify edited scene
- H-category (animation/tween): N/A
- I-category (input): N/A — uses SpinBox built-in input
- J-category (save/load): N/A
- K-category (UI/theme): PASS — all colors from editor theme
- L-category (UndoRedo): PASS — single action per commit; merging for drag
- M-category (mobile): SKIP — desktop only per intent doc
- N-category (compatibility): PASS — uses 4.0+ APIs only
- O-category (security): N/A — no file I/O
- P-category (plugin metadata): PASS — plugin.cfg complete

Verdict: 64 patterns walked; 0 matches.

### Clean Code review (Clean Code Officer)
- Conceptual cohesion: SOLID
- Coupling discipline: SOLID
- Naming honesty: SOLID
- Concept layering: SOLID — domain/vector_field_math has no Godot editor deps
- Reversibility: SOLID
- Testability: SOLID — vector_field_math.gd unit-testable
- Documentation alignment: SOLID

### Clean Architecture Manifesto check (Architectural Quality Auditor)
- Invariant 1 (system = responsibility): PASS — 4 systems, 4 sentences, no "and"s
- Invariant 2 (file = job): PASS — 5 files, 5 one-phrase jobs
- Invariant 3 (function = operation): PASS — verified by reading
- Invariant 4 (signals/events for cross-system): PASS — no reaching-through
- Invariant 5 (no hardcoded config): PASS — drawer uses @export for tunables; theme colors from EditorInterface
- "Doesn't fall apart" test: 
  - Adding next feature (e.g., color field variant) touches ~2 files ✓
  - Removing direction_indicator breaks only drawer.gd's compose code ✓
  - New engineer finds VECTOR_FIELD via README → inspector_plugin.gd path ✓
  - 3× growth (10 hint variants) would be additive, not structural rework ✓

### Consistency cross-check
```
bash scripts/consistency-cross-check.sh --ticket=TKT-001 --plugin=addons/vector_field_inspector
> No same-subject conflicts
> No architecture drift
> README terms match code
> No ADR violations
> 0 contradictions
```

### Pipeline runs
```
bash scripts/full-pipeline.sh addons/vector_field_inspector --ticket=TKT-001 --size=L --mode=standard

[... 20 stages, all PASS or appropriate MANUAL verification ...]

✓ STANDARD MODE PIPELINE PASSED
Runtime: 22 minutes
```

### Honesty Audit (final)
- Every API reference verified against XML ✓
- No claims about behavior not tested ✓
- README examples actually work ✓

### Sign-off
- DoD Steward: all acceptance criteria met ✓
- Quality Gate Officer: all L-tier gates PASS ✓
- Tech Director: signed ✓

Phase 1.G closes. Ticket can ship.

---

## Final deliverable

```
addons/vector_field_inspector/
├── plugin.cfg                                # 12 lines
├── README.md                                 # 85 lines
├── icon.png                                  # 16x16
├── core/
│   └── plugin.gd                             # 28 lines
├── inspector/
│   ├── inspector_plugin.gd                   # 32 lines
│   └── drawer.gd                             # 145 lines
├── ui/
│   └── direction_indicator.gd                # 58 lines
└── domain/
    └── vector_field_math.gd                  # 42 lines

Total: ~410 lines across 8 files.
```

Five days of work (1 day each for phases 1.A-1.E combined, 2 days for Phase 1.F across 8 sub-tasks, 1 day for Phase 1.G audits).

---

## What this looks like in conversation

The user's actual messages during this ticket (illustrative compression):

> **User:** I want a plugin where I can use @export_custom(PROPERTY_HINT_VECTOR_FIELD, '') ...
> 
> **Studio:** [Phase 1.A] Let me confirm I understand: you want a custom inspector drawer for Vector3 properties with a specific hint, showing XYZ inputs plus a 2D direction visualization, with undo/redo working as expected. Out of scope: 3D viewport gizmo, multi-select editing, animation. Is that right?
> 
> **User:** yes
> 
> **Studio:** [Phase 1.B] One catch — PROPERTY_HINT_VECTOR_FIELD isn't a built-in Godot 4.6.2 hint. Suggest using @export_custom(PROPERTY_HINT_NONE, 'VECTOR_FIELD') — same end result, plugin filters by hint string. OK?
> 
> **User:** ok
> 
> **Studio:** [Phase 1.C] Three approaches considered: in-inspector drawer (the conservative choice), side-panel companion (more room but discoverability issue), 3D viewport gizmo (best UX but explicitly out of scope). Going with in-inspector drawer. ARB approved. Architecture has 4 modules: core, inspector, ui, domain. Folder layout matches standard manifesto.
> 
> **User:** [implicit "ok, proceed"]
> 
> **Studio:** [Phase 1.D-G run; ~5 days work; periodic updates] Done. 410 lines across 8 files. Pipeline passed all 20 standard-mode stages. README documents the @export_custom syntax. Tested with sample VECTOR_FIELD properties. Ready to install at addons/vector_field_inspector/.

The user does not see Phases 1.A-1.G as named events; they see updates at meaningful points. Behind the scenes, all 8 phases ran with full audit trail.

---

## What if a phase fails

The walkthrough above shows a clean run. Real tickets often have failures along the way. The studio's response when, say, Phase 1.E (Architecture Gate) FAILs:

> **Studio:** Architecture Veto Officer raised an issue with the proposed design. The drawer was reaching into the inspector_plugin's internals to refresh on object changes. Spaghetti indicator (S-012: Reaching Into). Sending back to Phase 1.C to add a refresh signal instead. Should add ~30 minutes. OK to proceed?
> 
> **User:** ok
> 
> [Phase 1.C re-opens; signal added; ARB re-approves; Phase 1.E PASSes second time]

The studio doesn't hide failures from the user. It explains what was caught and what the fix is.

---

## Patterns this cookbook demonstrates

1. **User intent stays at the top.** Phase 1.A's intent doc is referenced throughout. Drift would be caught by Consistency Auditor.

2. **Architecture before code.** No `.gd` files written until Phase 1.E passes. This is the v2.0 hill.

3. **Wire-as-you-build.** Sub-tasks close only with wiring verified. Integration is not a final-step cleanup.

4. **Manifesto-driven structure.** Folder layout comes from the manifesto, not invented per-ticket.

5. **Catalogs walked.** 64 defect patterns considered even when most are N/A. The walk is fast (10-15 minutes) because most patterns clearly don't apply.

6. **Honest user communication.** The user sees decisions and progress, not every internal audit.

7. **All deferred items tracked.** DEF-002 (small indicator risk) captured; will resurface if user reports issue.

This is what the studio does. Read it once; reference it when in similar territory.
