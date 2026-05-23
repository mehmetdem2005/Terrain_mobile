# Quality Gates

This is the studio's sign-off rulebook. The Quality Gate Officer runs these checks at the end of every ticket. Nothing passes without all required checks for its size class returning PASS.

## Universal gate (applies to every ticket regardless of size)

These checks run on every ticket, even an S. If any fail, ticket → BLOCKED.

| # | Check | How verified | Owner role |
|---|-------|--------------|-----------|
| U1 | All claimed Godot APIs exist in 4.6.2 | grep against `~/godot-api-reference/<Class>.xml` for every API mentioned in the final artifact | API Verification Specialist |
| U2 | Final code parses cleanly | `godot --headless --check-only <file>` returns exit 0 | GDScript Language Specialist |
| U3 | No unverified claims in audit trail | Honesty Auditor sweep | Honesty Auditor |
| U4 | Acceptance criteria all marked verified | Each criterion in ticket has a corresponding PASS entry in audit trail | Quality Gate Officer |
| U5 | Audit trail is complete | Every active role in the roster has at least one logged action | Process Auditor |
| U6 | Final artifact paths exist on disk | `ls` confirms files at the paths claimed in the ticket's `final_artifact_paths` | Build Engineer |

## S — Trivial (1-line fix, typo, comment, default value change)

Universal gate, plus:

| # | Check | How verified | Owner role |
|---|-------|--------------|-----------|
| S1 | Change is genuinely scoped to S | Diff is small enough to read in one glance; OR is a single-property tweak / typo fix / one-config-value change | Tech Director (during triage) |
| S2 | No unintended side effects | grep the rest of the codebase for usages of the changed line/identifier; confirm not breaking | Tools Engineer |

S tickets have no Polish, Performance, or Security mandatory checks. If the work needs those, it is misclassified — escalate to M and re-triage.

## M — Small (single file, single feature, <100 new LOC)

Universal gate + S gate, plus:

| # | Check | How verified | Owner role |
|---|-------|--------------|-----------|
| M1 | Static analysis clean | `gdlint addons/<plugin>/` exits 0 OR all warnings are explicitly justified in audit trail | Static Analysis Engineer |
| M2 | Formatting consistent | `gdformat --check addons/<plugin>/` exits 0 | Coding Standards Enforcer |
| M3 | No deprecated API usage | Cross-check claims against `references/godot-4.6.2-api-pitfalls.md` deprecation list | API Verification Specialist |
| M4 | Polish pass complete | Polish Lead reviewed and signed; trivial niceties (consistent naming, useful errors, sensible defaults) confirmed | Polish Lead |
| M5 | One smoke test passed | A minimal scenario that exercises the change runs without error | QA Lead |

## L — Medium (new plugin component, multi-file, <500 LOC, single platform)

Universal gate + S gate + M gate, plus:

| # | Check | How verified | Owner role |
|---|-------|--------------|-----------|
| L1 | Plugin loads in Godot editor | `godot --headless --quit --editor --path <test-project>` exits 0 with no error logs | Build Engineer |
| L2 | Plugin disables cleanly | Editor reload after disable shows no leaked nodes / no error logs | Build Engineer + Resource Leak Auditor |
| L3 | `_enter_tree` / `_exit_tree` symmetric | Every `add_*` call in `_enter_tree` has a matching `remove_*` in `_exit_tree` | Editor Integration Engineer |
| L4 | Signal connections symmetric | Every `connect()` call has a matching `disconnect()` (or is justified as one-shot via `CONNECT_ONE_SHOT`) | Signal System Specialist |
| L5 | Undo/Redo works for any user-visible mutation | UndoRedo Specialist confirmed undo and redo restore state correctly for each mutating action | UndoRedo Specialist |
| L6 | Performance budget met | Plugin startup <50ms; inspector refresh <16ms; editor frame time impact <2ms steady-state | Performance Budget Officer |
| L7 | Memory budget met | No growing allocation under repeated enable/disable cycles | Memory Specialist |
| L8 | Edge cases hunted | Edge Case Hunter has documented at least 5 attempted edge cases; the plugin survives them or fails gracefully | Edge Case Hunter |
| L9 | Crash safety | Crash Auditor confirmed null-safety in all `_ready` / `_enter_tree` / event handler paths | Crash Auditor |
| L10 | Security review | File I/O paths sanitized; no arbitrary code execution paths; no unsafe deserialization | Security Reviewer |
| L11 | Documentation present | At minimum: `addons/<plugin>/README.md` exists with installation, basic usage, and known limitations | Technical Writer |
| L12 | Devil's Advocate review | Red team attempt to break the plugin has been logged | Devil's Advocate |
| L13 | Consistency check | No contradictions in audit trail; all roles' positions reconciled | Consistency Auditor |
| L14 | Risk register updated | Any risks identified during work are logged in `.studio/knowledge-base/risks.md` | Risk Officer |
| L15 | CI/CD checks pass | `bash scripts/ci-checks.sh` runs all M/L checks in one go and returns 0 | CI/CD Engineer |
| L16 | End-user perspective | End-User Advocate has reviewed the plugin's user-facing surface and approved it | End-User Advocate |
| L17 | Definition of Done satisfied | DoD Steward confirms every item in the L DoD checklist is met | Definition of Done Steward |
| **L18** | **Forward wiring clean** | `bash scripts/wiring-audit.sh` returns 0; every new public function/signal has callers/listeners | Integration Engineer |
| **L19** | **Reverse wiring clean** | `bash scripts/reverse-wiring-audit.sh` returns 0; every new file is referenced | Integration Engineer |
| **L20** | **Dead code clean** | `bash scripts/dead-code-scan.sh` shows no true dead code (deferred or annotated items OK) | Dead Code Hunter |
| **L21** | **Orphan references clean** | Every `preload`/`load`/class_name reference resolves to an existing target | Orphan Reference Hunter |
| **L22** | **Semantic dependency audit complete** | Every new/changed concept walked through the 7-question audit; applicable catalog rules addressed | Semantic Dependency Engineer |
| **L23** | **Impact analysis complete** | Every public-API symbol change has a corresponding impact report; all affected files addressed or deferred | Impact Analysis Engineer |
| **L24** | **Phase gates all passed** | Phases 1.A through 1.G each have PASS or PASS_WITH_CONDITIONS verdict in audit trail | Process Auditor + Tech Director |
| **L25** | **Architecture Veto passed** | Phase 1.E verdict is PASS or PASS_WITH_CONDITIONS (not FAIL, and not bypassed without override record) | Architecture Veto Officer |
| **L26** | **Deferred items tracked** | Every "later" item has a DEF-NNN file with resurfacing condition and owner | Audit Trail Officer |
| **L27** | **Defect pattern walk complete** | Defect Pattern Specialist walked all 64+ patterns from `godot-4.6.2-defect-catalog.md`; matches addressed or deferred | Defect Pattern Specialist |
| **L28** | **Concurrency hunt complete** | Concurrency Bug Specialist examined signal chains, call_deferred sites, tween lifetimes, reentrancy hazards | Concurrency Bug Specialist |
| **L29** | **State corruption hunt complete** | State Corruption Specialist identified and tested invariants; partial-state recovery verified | State Corruption Specialist |
| **L30** | **Adversarial Hunt (XL only)** | 30+ minute combined session by Devil's Advocate + Edge Case Hunter + 3 bug specialists; report in audit trail | Bug Hunter Lead |
| **L31** | **Clean Code Officer review passed** | Per-criterion verdict (conceptual cohesion, coupling discipline, naming honesty, concept layering, reversibility, testability, doc alignment) is PASS or PASS_WITH_CONDITIONS | Clean Code Officer |
| **L32** | **Spaghetti scan clean** | Tier 1 patterns from `spaghetti-pattern-catalog.md` (God Module, Lying Name, Wide Environment, Manager God, Tangled Function, Forever Temporary) all absent or justified | Clean Code Officer |
| **L33** | **Architectural quality matches design** | Call graph, data ownership, lifecycle thread match Phase 1.C design intent (no silent drift) | Architectural Quality Auditor |
| **L34** | **Senior-engineer pride test** | Code reads as work a senior engineer at AAA studio would be proud of | Clean Code Officer + Architectural Quality Auditor |
| **L34a** | **Manifesto Invariant 1: One system = one responsibility** | Each system has a one-sentence responsibility; no "and" conjunctions | Architectural Quality Auditor |
| **L34b** | **Manifesto Invariant 2: One file = one clear job** | Every file has a one-phrase job; no vague catch-all files | Clean Code Officer |
| **L34c** | **Manifesto Invariant 3: One function = one operation** | Functions do one thing; name matches body; no Tangled Functions | Clean Code Officer |
| **L34d** | **Manifesto Invariant 4: Systems communicate by signals/events** | No reaching-through patterns; cross-system calls via signals or defined interfaces | Architectural Quality Auditor |
| **L34e** | **Manifesto Invariant 5: Configuration not hardcoded** | Magic numbers/strings replaced by @export, const, or resources | Clean Code Officer |
| **L34f** | **"Doesn't fall apart when it grows" test** | Adding feature is bounded to a small file count; removing module breaks only easily-updatable callers; structure is discoverable; would scale several times without rework. Indicators, not hard numbers. | Architectural Quality Auditor |
| **L34g** | **Folder structure matches manifesto standard** | Layout follows `clean-architecture-manifesto.md` standard or has justified deviation in Phase 1.C | Architectural Quality Auditor |
| **L35** | **3 alternatives documented** | Phase 1.C produced 3 meaningfully different alternatives (not cosmetics of one); at least one is unconventional | Innovation Scout |
| **L36** | **Trade-off matrix complete** | 8-dimension comparison matrix produced for the 3 alternatives; selection rationale explicit | Trade-off Analyst |
| **L37** | **No alternative theater** | The 3 alternatives are genuinely considered (not "I picked A and wrote 2 sentences each for B/C") | ARB at Phase 1.E |
| **L38** | **Full pipeline PASS** | `bash scripts/full-pipeline.sh <plugin_dir> --ticket=TKT-NNN --size=L` returns 0; all 30 stages PASS or properly SKIPPED | Pipeline Orchestrator |
| **L39** | **Consistency cross-check clean** | `bash scripts/consistency-cross-check.sh --ticket=TKT-NNN` returns 0; 0 contradictions across audit trail | Consistency Auditor (enhanced) |
| **L40** | **Pipeline report archived** | Unified gate report saved to ticket's `pipeline-report.md`; permanent part of audit trail | Pipeline Orchestrator |
| **L41** | **Lesson harvest complete** | `<ticket>/lessons.md` exists with 1-5 entries, each in strict format (category, tags, context, lesson, evidence, confidence); Curator approved | Studio Knowledge Curator |
| **L42** | **Index updated** | New lessons appear in `.studio/knowledge-base/index.md` with correct category/tag/back-link; index syntactically valid | Studio Knowledge Curator |
| **L43** | **Pre-ticket consult performed (at Phase 1.B)** | `<ticket>/relevant-lessons.md` exists; matched lessons cited with reasoning OR "no match" justified; ticket plan accounts for matches | Tech Director |
| **L44** | **Repeat-mistake check clean** | Honesty Auditor reviewed defects-found against knowledge index; either no repeat found OR `repeat-mistake-postmortem.md` exists and is signed off; original lesson confidence bumped | Honesty Auditor |
| **L45** | **Risk Register exists and is format-valid** | `<ticket>/risk-register.md` produced at Phase 1.B close; each risk has probability, impact, category, source, description, mitigation, owner, trigger | Risk Officer |
| **L46** | **Medium-or-above risks tied to plan sub-tasks** | Every medium/high probability × medium/high/critical impact risk has at least one mitigation sub-task in Phase 1.D plan, explicitly cited | Risk Officer + Tech Director |
| **L47** | **Risk-handling row in trade-off matrix** | Phase 1.C trade-off matrix contains a row per medium-or-above risk showing how each alternative handles it; Architecture Veto consumes this at Phase 1.E | Trade-off Analyst |
| **L48** | **Reconciliation complete at Phase 1.G** | `risk-register.md` reopened; every R-N has an outcome entry (mitigated/materialized/ducked/accepted) with evidence; new-surfaced risks numbered and described | Risk Officer |
| **L49** | **Lesson candidates from materialized risks identified** | Materialized risks reviewed with Curator at Phase 1.G; lesson candidates either harvested into `lessons.md` or explicitly dismissed with reasoning | Risk Officer + Studio Knowledge Curator |
| **L50** | **Ticket fingerprint complete** | `<ticket>/ticket-fingerprint.md` exists at Phase 1.C close; every fingerprint axis answered yes/no/unsure; relevant catalog categories summarized | Defect Pattern Specialist |
| **L51** | **Predictive checklist complete and integrated** | `<ticket>/predictive-checklist.md` walks every relevant catalog category; every APPLIES pattern tied to a Phase 1.D sub-task; every DOESN'T APPLY has reasoning; Tech Director countersigned | Defect Pattern Specialist + Tech Director |
| **L52** | **Plan predictive-coverage annotations complete** | Every Phase 1.D sub-task either annotated with "predictive coverage" line citing covered patterns OR explicitly states "no patterns apply — covered elsewhere" | Tech Director |
| **L53** | **Predictive vs actual reconciliation complete (Phase 1.G)** | `predictive-vs-actual.md` exists; predicted APPLIES verified (worked or fixed); predicted DOESN'T APPLY re-verified; unpredicted matches fed to Knowledge Loop as lesson candidates with fingerprint-gap analysis | Bug Hunter Lead + Defect Pattern Specialist |
| **L54** | **Checkpoints exist for every completed phase boundary** | `.studio/checkpoints/TKT-NNN-phase-1.X/` populated for each phase transition; checkpoint contains ticket-state.json, audit-trail snapshot, artifacts, summary | Audit Trail Officer |
| **L55** | **Rollback triggers monitored throughout execution** | Either no triggers fired (documented in close review) OR triggers fired and were processed via L56 | Rollback Officer |
| **L56** | **Rollback decisions are structured** | Any rollback request produced a `rollback-decision.md` walking all five dimensions (validity, scope, cost forward, cost back, decision); continuation decisions have documented forward-looking reasoning | Rollback Officer |
| **L57** | **No sunk-cost reasoning in continuation decisions** | Honesty Auditor reviewed every `rollback-decision.md`; no "we already spent X" or equivalent arguments survived; any flagged decisions were re-evaluated forward-looking | Honesty Auditor |

## L (game tickets) — additional gates beyond L1-L40

For tickets where the deliverable is game code (not plugin code), the following gates apply in addition to L1-L40. The Tech Director marks a ticket as a "game ticket" during triage; this activates departments 15-19 and the gates below.

| # | Check | How verified | Owner role |
|---|-------|--------------|-----------|
| **G1** | **Gameplay-loop separation** | Logic in `_physics_process` for physics; `_process` for visuals/UI; no crossover (game catalog GAME-DEF-002, GAME-DEF-003) | Game Architecture Lead |
| **G2** | **Frame-rate independence** | Movement / time-based effects all delta-multiplied; tested at 30fps and 144fps (game catalog GAME-DEF-001) | Gameplay Engineer |
| **G3** | **Scene lifecycle safety** | No "previously freed object" risks; `is_instance_valid` guards where references cross scenes; no leaked nodes on scene change (GAME-DEF-009, GAME-DEF-010) | Scene Architecture Specialist |
| **G4** | **Autoload discipline** | Autoload count ≤ 5; each is a true global with explicit justification; no manager-god-objects (GAME-DEF-012, GAME-ARCH-001) | Game Architecture Lead |
| **G5** | **Save schema versioned + recovery** | Save dict has `version` field; migration path exists for any schema change; atomic write to `user://` with `.bak` (GAME-DEF-025, GAME-DEF-027, GAME-DEF-029) | Save System Engineer |
| **G6** | **State machine explicit** | Entity state via enum + transition function, not 4+ booleans; entry/exit logic centralized (GAME-DEF-031, GAME-DEF-032) | Gameplay Engineer |
| **G7** | **Performance budget honored** | Frame time stays within target on reference hardware (60 fps desktop / 30 fps mobile by default; tunable per game) | Game Performance Officer |
| **G8** | **Game-defect catalog walk** | Defect Pattern Specialist walked relevant categories of `game-defect-catalog.md`; matches addressed or deferred | Defect Pattern Specialist |
| **G9** | **Mobile considerations (if mobile target)** | Renderer set to Mobile; touch input mapped; sustained-performance considered; battery awareness in menus (GAME-DEF-051 through GAME-DEF-057) | Mobile Game Performance Specialist |
| **G10** | **Multiplayer authority (if multiplayer)** | Server-authoritative model OR explicit trust assumptions documented; RPC sender validation present (GAME-DEF-040, GAME-DEF-042) | Multiplayer Engineer |
| **G11** | **Audio polyphony and bus routing** | All audio through named buses; rapid triggers throttled; music transitions clean (GAME-DEF-058, GAME-DEF-059, GAME-DEF-061) | Audio Engineer |
| **G12** | **No hardcoded balance data** | Gameplay tuning values in `.tres` BalanceData resources or `@export` vars; designers can iterate without recompile (GAME-DEF-007 + Manifesto Invariant 5) | Gameplay Engineer |
| **G13** | **Composition over deep inheritance** | Entity hierarchy ≤ 3 deep; behaviors as components/nodes, not stacked inheritance (GAME-ARCH-005) | Game Architecture Lead |
| **G14** | **Persistent state separated from view state** | Save-relevant state lives in dedicated state object/autoload, not in scene-tree node properties that disappear on scene change (GAME-ARCH-006) | Save System Engineer |

## XL — Large (full new plugin OR multi-platform OR mobile-targeted)

Universal gate + S + M + L gates, plus:

| # | Check | How verified | Owner role |
|---|-------|--------------|-----------|
| X1 | Pre-production phase completed | Feasibility Analyst signed; Prior Art Research documented; Plugin Design Lead's design doc exists | Tech Director |
| X2 | Architecture Review Board approval | All 3 ARB seats voted; ADR(s) recorded for major decisions | Architecture Review Board |
| X3 | Cross-platform check (if multi-platform) | Tested on each target platform — actual launch in Godot editor on each | Cross-Platform Compatibility Engineer |
| X4 | Mobile renderer compatibility (if mobile) | Plugin tested in Forward Mobile renderer; no Forward+-only features used; HDR/glow/DoF avoidance confirmed | Mobile Renderer Specialist |
| X5 | Android Editor compatibility (if Android Editor targeted) | Plugin loads in Godot Android Editor; touch input handled; small-screen layout works | Android Editor Specialist |
| X6 | Mobile performance budget (if mobile) | 60fps mid-tier Android; <50MB RAM overhead; thermal stable over 5min loop | Mobile Performance Specialist |
| X7 | API stability declared | Public API surface documented with SemVer commitment; breaking change risks called out | API Stability Officer |
| X8 | Data migration path (if plugin stores user data) | Forward/backward migration strategy documented | Data Migration Engineer |
| X9 | Tutorial documentation | At least one cookbook-style walkthrough exists alongside the API reference | Tutorial Writer |
| X10 | Onboarding test | An "untouched developer" simulated journey through the plugin works (Onboarding Tester role) | Onboarding Tester |
| X11 | Localization readiness (if user-facing strings) | All editor-facing strings go through `tr()`; translation file template generated | Localization Engineer |
| X12 | Accessibility check | Keyboard navigation works; screen reader compatibility considered; contrast meets WCAG | Accessibility Engineer |
| X13 | Beta test plan | Beta Test Coordinator has defined a beta cohort and success criteria | Beta Test Coordinator |
| X14 | Asset Library readiness | `plugin.cfg` is complete and conformant; icon present; license declared; sample project optional but recommended | Asset Library Readiness Officer |
| X15 | License audit | All third-party code (if any) properly attributed and license-compatible | License Auditor |
| X16 | Release notes | Human-readable release notes drafted (Technical Writer + Release Manager) | Release Manager |
| X17 | Fuzz / stress test | Fuzz Test Engineer ran random inputs / repeated cycles / large data; no crashes | Fuzz Test Engineer |
| X18 | Reproduction harness | Reproduction Engineer has a documented method to reproduce any reported issue | Reproduction Engineer |
| X19 | Postmortem readiness | Postmortem Lead has the audit trail captured; will write retrospective on closure | Postmortem Lead |
| X20 | Studio Head sign-off | Studio Head has personally reviewed the deliverable summary and approved | Studio Head |

## XL (game tickets) — additional gates

For XL tickets that are game projects (not plugin projects), add these on top of X1-X20 and L's game-ticket additions G1-G14:

| # | Check | How verified | Owner role |
|---|-------|--------------|-----------|
| **GX1** | **Sustained playtest** | Game ran continuously for ≥10 minutes on target hardware without crash, leak, or framerate collapse | QA Lead + Game Performance Officer |
| **GX2** | **Save round-trip on full game state** | Save → quit → relaunch → load → state is identical (no silent corruption); tested across 3+ varied game states | Save System Engineer |
| **GX3** | **Scene transition stress** | 50+ scene transitions in a session; no memory growth; no leaked nodes | Scene Architecture Specialist |
| **GX4** | **Multiplayer disconnect handling (if multiplayer)** | Each peer disconnect path tested: host quits, client quits, network failure, timeout — game responds gracefully (GAME-DEF-045) | Multiplayer Engineer |
| **GX5** | **Mobile sustained-thermal (if mobile)** | Game runs ≥15 minutes on physical device without thermal throttling causing frame collapse | Mobile Game Performance Specialist |
| **GX6** | **Input device coverage** | Each declared input device class tested: keyboard+mouse, controller, touch (per platform target) | Gameplay Engineer |
| **GX7** | **Accessibility — game-specific** | Color-blind palette options where color carries meaning; subtitles for important audio; remappable controls | Accessibility Engineer |
| **GX8** | **Localization scaffold (if multi-language)** | All player-facing strings via `tr()`; CSV translation file present; tested with at least one non-English locale | Localization Engineer |
| **GX9** | **Game-feel review** | Game Designer + End-User Advocate playtested; "feels good" verdict with specific findings (input latency, animation snap, audio reactivity) | Game Designer |
| **GX10** | **Adversarial gameplay hunt (XL only)** | 30+ min combined session: Bug Hunter Lead + Concurrency Specialist + State Corruption Specialist + Game Designer attack the game from player-as-adversary angle | Bug Hunter Lead |

## What "PASS" means for each check

A check returns PASS when:
1. The owning role has performed the verification action (logged in audit trail)
2. The action's result was unambiguously positive (e.g., exit code 0, grep found the API, no warnings)
3. The result is recorded with concrete evidence (command run, output captured, file/line referenced)

A check returns FAIL when:
1. The verification action returned a negative result
2. The verification was not performed (counts as FAIL — no benefit of the doubt)
3. The result is ambiguous and cannot be made unambiguous

Any FAIL halts the gate and raises a blocker against the responsible role.

## What "PASS with conditions" means

Sometimes a check is *contingent* on an assumption that cannot be verified within the studio (e.g., "user confirmed they don't need Windows support"). In these cases the check passes WITH CONDITIONS:

```json
{
  "check_id": "X3",
  "result": "PASS_WITH_CONDITIONS",
  "conditions": [
    "User explicitly waived Windows compatibility on 2026-05-21 (see ticket audit trail line 84)"
  ]
}
```

The conditions become permanent ticket metadata. If a downstream issue arises that traces back to one of these conditions, the postmortem cites it.

## Honesty Auditor's final pass — what it actually looks at

After Quality Gate completes, Honesty Auditor performs this exact sequence:

1. **Extract every API reference from the final artifact.** Use `grep -E '[A-Z][a-zA-Z0-9]*\.[a-z_][a-zA-Z0-9_]*' <files>` plus knowledge of Godot's class naming.
2. **For each, find the corresponding verification entry in the audit trail.** If missing → BLOCKER.
3. **Check every `[ASSUMPTION]` marker.** Was it acknowledged by the user? If not → BLOCKER.
4. **Scan for hedging language in the audit trail.** Any "should work", "probably", "I think" that lacks a verification entry within 5 lines → BLOCKER.
5. **Spot-check 3 random API claims** by independently running the grep/check-only verification. If any disagrees with the audit trail → CRITICAL BLOCKER + Accuracy score hit for the responsible role.
6. **Verify all code blocks have been parse-checked.** Any code block in the final artifact that does not have a corresponding `godot --check-only` entry → BLOCKER.

Only after all six steps return clean does the ticket advance to SIGN_OFF.

## Override protocol

Anyone except the Honesty Auditor can be overridden by a higher-ranked role. Honesty Auditor's veto can only be overridden via:

```json
{
  "override_id": "OVR-007-01",
  "overriding_role": "Studio Head",
  "overridden_blocker": "BLK-007-04",
  "rationale": "User explicitly accepted the unverified claim about Inspector.add_section because they will manually verify in their environment. See ticket audit trail line 92 for user sign-off.",
  "permanent_record": ".studio/knowledge-base/overrides.md",
  "auto_postmortem_ticket_id": "TKT-008"
}
```

Overrides are expensive on purpose:
- They require Tech Director or Studio Head signature
- They auto-create a postmortem ticket to evaluate whether the override should have happened
- They appear permanently in the studio's institutional memory

Most engineers, faced with this, just fix the underlying issue.

## Definition of Done — by size class

These are summary checklists the Definition of Done Steward maintains. They are derived from the gate tables above.

### DoD for S
- [ ] Universal U1–U6
- [ ] S1–S2

### DoD for M
- [ ] S DoD complete
- [ ] M1–M5

### DoD for L
- [ ] M DoD complete
- [ ] L1–L17

### DoD for XL
- [ ] L DoD complete
- [ ] X1–X20

The DoD Steward signs the final DoD as PASS only when every box is checked with a corresponding audit trail entry.

---

## v2.1 Game development gates

These gates activate ONLY for game tickets (per Tech Director's domain triage). They run in addition to (not instead of) the existing L/XL gates, at Phase 1.G alongside the standard pipeline stages. For M-tier game tickets, only the gates relevant to the touched system run; for L/XL game tickets, all applicable ones run.

| Gate | Check | Owner |
|------|-------|-------|
| **G-1** | Framerate stable on target platform at target scene | Framerate Auditor — measures min/avg/95th percentile fps in the affected scene on the target device class. No spike frames over 2x budget without justification. |
| **G-2** | Memory budget under target | Memory Auditor — checks RSS / Godot memory monitor against target platform budget. No leaks between scene loads. |
| **G-3** | Loading time within budget | Loading Time Auditor — times scene transitions and first-frame time. Mobile target: under 3s typical. |
| **G-4** | Save roundtrip clean (when save touched) | Save Integrity Auditor — runs 5-test checklist: roundtrip, version migration, corruption recovery, partial-field recovery, backup load. |
| **G-5** | Multiplayer state consistency (when applicable) | Multiplayer Sync Auditor — verifies authority model, no client-trusted gameplay, MultiplayerSpawner/Synchronizer setup correct, disconnect handled. |
| **G-6** | Game feel acceptable (player-facing changes) | Game Feel Auditor — plays the affected scenario; reports on input latency, animation responsiveness, audio sync. Qualitative but mandatory for player-facing changes. |
| **G-7** | Autoload count justified | Game Architecture Lead — every autoload passes the 3-question test (truly global? accessed from many places? scene-local won't work?). New autoloads in this ticket explicitly justified. |
| **G-8** | State machines explicit (no implicit boolean tangles) | Architectural Quality Auditor — character/game state implemented as explicit FSM/HSM/BT pattern, not boolean flag tangles. Each state has clear enter/exit symmetry. |

### Game DoD additions

For game tickets, the DoD extends:

#### Game M ticket DoD additions
- [ ] G-1 if performance-affecting
- [ ] G-4 if save-touching
- [ ] G-6 if player-facing

#### Game L ticket DoD additions
- [ ] G-1, G-2, G-3 (performance baseline)
- [ ] G-4 if save-touching
- [ ] G-5 if multiplayer-touching
- [ ] G-6 (player-facing changes audited)
- [ ] G-7 (autoload audit)
- [ ] G-8 (state machine clarity audit)

#### Game XL ticket DoD additions
- [ ] All L additions
- [ ] G-1 measured across multiple scenarios (not just one happy-path scene)
- [ ] G-2 measured after extended-play simulation (catches leaks)
- [ ] G-3 measured for cold start AND scene transitions AND save load
- [ ] G-4 full 5-test save integrity battery
- [ ] G-6 on multiple player skill levels (new player vs experienced)

### Game ticket pipeline runtime estimates

Adding G-1 through G-8 increases pipeline runtime for game tickets:

| Mode | Plugin ticket | Game ticket |
|------|--------------|-------------|
| Lite | <5 min | <10 min (G-1 + G-4 only if applicable) |
| Standard | 15-30 min | 30-45 min |
| Full | 1-2 hr | 1.5-2.5 hr |

The runtime difference reflects real additional work: actually playing the game scenarios, measuring framerate over time, running save corruption tests. Game tickets are not cheaper than plugin tickets; they have different cost profiles.

---

End of Quality Gates. For how new roles get spun up when a ticket reveals a domain none of the existing 100+ roles cover, see `role-instantiation-protocol.md`.
