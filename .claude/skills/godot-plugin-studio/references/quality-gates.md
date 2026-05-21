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
| S1 | Change is genuinely scoped to S | Diff is ≤5 lines OR is a single-property tweak | Tech Director (during triage) |
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

End of Quality Gates. For how new roles get spun up when a ticket reveals a domain none of the existing 86 roles cover, see `role-instantiation-protocol.md`.
