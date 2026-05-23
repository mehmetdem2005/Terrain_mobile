# Cost-Aware Execution Modes

The studio's full pipeline has 30 stages. For an XL ticket touching multi-module architecture, that's appropriate. For an S ticket fixing a typo, it's absurd overhead.

This protocol defines three **execution modes** — Lite, Standard, Full — and the rules for choosing among them. The Tech Director picks the mode at ticket triage. The Pipeline Orchestrator runs the matching subset.

The studio does not believe in "always run everything." Studios that do are wasting effort. The studio believes in running **the right checks for the work being done**.

---

## Why modes exist

The user's implicit concern (captured during v2.0 retrospective): if every plugin ticket runs a 30-stage pipeline that takes 2+ hours, the studio is unusable for small work. AAA studios don't run their full release-validation suite on every commit; they have lightweight pre-commit checks, deeper checks at PR time, and full release validation only at release time.

Modes are the studio's equivalent.

---

## The three modes

### Lite mode

**When:** S tickets, U tickets (urgent hot-fixes), single-character bug fixes
**Pipeline stages run:** 8 of 30
**Estimated time:** under 5 minutes
**Skipped:** semantic dependency walks, bug hunts, clean code review, 3-alternative, full architectural audit, full consistency cross-check, adversarial hunts

**Stages included:**
1. Environment verification
2. Setup integrity
3. File integrity
4. Parse check
5. gdformat
6. gdlint
7. plugin.cfg conformance (if applicable)
8. Honesty Audit (claims verified)

**Rationale:** The work is too small to justify the full battery. The risks the full pipeline catches (broken architecture, missed dominoes, dead code accumulation) don't materialize from a 1-line fix.

**Override:** any role can flag "this S ticket is actually riskier than it looks" — Tech Director re-evaluates and may upgrade to Standard.

---

### Standard mode

**When:** M tickets, most L tickets
**Pipeline stages run:** 20 of 30
**Estimated time:** 15-30 minutes
**Skipped:** Adversarial Hunt (XL-only), 3-alternative documentation (XL-only), full architectural quality audit (replaced with focused check), Cross-Domain Pattern Specialist consultation

**Stages included (the 8 Lite stages plus):**
9. Phase gate audit (Phases 1.A-1.G have verdicts)
10. API verification scan
11. Cross-impact scan (for symbol changes)
12. Semantic dependency walk (relevant categories only, not full 100+)
13. Forward wiring audit
14. Reverse wiring audit
15. Dead code scan
16. Defect pattern walk (top 20 patterns, not full 64)
17. Clean Code review (focused on changed files)
18. Spaghetti scan (Tier 1 patterns only)
19. Deferred items tracked
20. Documentation freshness (if user-facing changes)

**Rationale:** M and L tickets do real work. Architecture matters, domino effects matter, clean code matters. But the work is bounded enough that XL-tier checks (full 64-pattern walk, Adversarial Hunt, full architectural audit) are excessive.

---

### Full mode

**When:** XL tickets, release candidates, anything user-flagged "high stakes"
**Pipeline stages run:** All 30
**Estimated time:** 1-2 hours
**Skipped:** none

**Rationale:** XL tickets touch many modules, introduce significant new surface, and have higher risk. Release candidates are the studio's name on the line. The full pipeline is the studio's commitment to AAA quality at these moments.

---

## Mode selection at triage

The Tech Director (during ticket triage in `coordination-protocol.md`) picks the mode based on ticket characteristics. Not just size — characteristics:

| Characteristic | Implication |
|----------------|-------------|
| Touches plugin.cfg or `_enter_tree`/`_exit_tree` | Upgrade by one mode (lifecycle is dangerous) |
| Adds new public API | Upgrade by one mode (surface change) |
| Modifies persistence schema | Upgrade by one mode (data risk) |
| Security-adjacent | Upgrade by one mode (security risk) |
| Adds dependency on new Godot API | Upgrade by one mode (compatibility risk) |
| Touches more than 5 files | Upgrade by one mode (breadth risk) |
| Hot-fix for shipped bug | Use Standard despite S size (regression risk) |
| Pure refactor (no behavior change) | Stay at original mode |
| Documentation-only | Stay at Lite |

If two upgrade-conditions apply, mode jumps two (e.g., Lite → Full). The Tech Director can also manually override based on judgment.

---

## What a Lite run looks like

```bash
$ bash scripts/full-pipeline.sh addons/my_plugin --ticket=TKT-042 --size=S --mode=lite

=== Godot Plugin Studio Pipeline (LITE) ===
Plugin: addons/my_plugin
Ticket: TKT-042
Size class: S
Mode: lite (8 stages)

✓ [ 1/ 8] Environment (Godot 4.x binary)            PASS  Godot 4.6.2
✓ [ 2/ 8] Setup integrity                           PASS
✓ [ 3/ 8] File integrity                            PASS  3 .gd files
✓ [ 4/ 8] Parse check                               PASS
✓ [ 5/ 8] gdformat                                  PASS
✓ [ 6/ 8] gdlint                                    PASS
✓ [ 7/ 8] plugin.cfg conformance                    PASS
? [ 8/ 8] Honesty Audit                             MANUAL  verify claims

=== Lite pipeline complete in 47 seconds ===
```

47 seconds. Appropriate for the work.

---

## When mode is wrong

If the studio runs Lite and a defect surfaces post-ship that would have been caught by Standard or Full: this is a triage failure. The Tech Director's mode pick is logged with the ticket; postmortem reviews:
- Was the mode appropriate for what we knew at triage?
- If yes: the defect was genuinely unforeseeable; no triage change
- If no: the mode-selection criteria need updating

This is how the studio's triage learns.

Conversely: if Full mode is consistently run on tickets where it surfaces nothing, that's also a signal. Maybe those tickets could safely be Standard. The Performance Analytics Engineer tracks this.

---

## Cost transparency for the user

When the user asks the studio to do work, they can ask: "How long will the pipeline take?"

Response template:
> This is being triaged as an M ticket in Standard mode. Pipeline takes ~20 minutes. If you want it faster (e.g., for an urgent fix), I can run Lite mode in ~5 minutes — but you accept that we skip semantic dependency walks, dead code scans, and clean code review. If you want it more thorough (e.g., this will be in production tomorrow), I can run Full in ~90 minutes.

The user makes the call when there's a real choice. The studio presents the trade-off honestly.

---

## What never gets skipped, regardless of mode

Some checks are non-negotiable:

- **Honesty Audit** — every claim about Godot APIs must be verified. Even Lite mode runs this. Lying claims are P0.
- **Parse check** — code that doesn't parse cannot ship. Even Lite runs this.
- **Plugin.cfg conformance** — if the plugin doesn't load, nothing else matters.
- **Setup integrity** — without Godot binary and gdtoolkit, the studio can't function.

These are the studio's minimum viable validation.

---

## What gets skipped only in extremis

Some checks are usually skipped only in Lite, but in genuinely urgent situations (production-down hotfix) even Standard can skip them:

- 3-alternative documentation (Phase 1.C)
- Adversarial Hunt
- Full 64-pattern defect walk
- Full architectural quality audit

When these are skipped under emergency conditions:
1. Audit trail records the emergency mode and the rationale
2. A follow-up ticket auto-creates to re-run the skipped checks within 48 hours
3. If the follow-up surfaces issues, the emergency fix is amended

The studio does not silently lower standards in a crisis. It explicitly lowers them, records the loan, and pays it back.

---

## Mode tracking in metrics

Per-ticket close, the studio records:
- Mode used
- Stages skipped (with justification)
- Issues found (per stage)
- Issues missed (caught post-ship; identified in retrospective)

Over time, this lets the studio calibrate: are the modes set right? Is the Tech Director's triage accurate? Are we over- or under-checking?

This calibration is what separates a real engineering organization from a checklist-driven one.

---

## Anti-pattern: Mode escalation as a security blanket

A failure mode the studio guards against: the Tech Director picks Full mode "just to be safe" on every ticket. This trains the studio toward Full, eliminates the cost-awareness this protocol introduced, and produces 2-hour pipelines for trivial work.

Audit Trail Officer reports per-quarter: what's the mode distribution? If Full is >40% of tickets, the Studio Head reviews — either the mode-selection criteria are wrong, or the Tech Director's risk tolerance is miscalibrated.

The right distribution for a healthy plugin development workflow is roughly: Lite 30-40%, Standard 50-60%, Full 5-15%. Game development workflows shift this slightly (see Faz 14-16 for game-dev specifics).

---

## Manual stages count for time estimation

Even Lite mode has manual stages (Honesty Audit is mode-skip-proof). The runtime estimates above include the time for manual stages — Honesty Audit takes 2-3 minutes for a Lite ticket, 10-15 minutes for a Full ticket.

When the user asks "how long?" the studio gives the full estimate, not just script runtime.

---

## Summary table

| Mode | Stages | Time | Use cases |
|------|--------|------|-----------|
| Lite | 8 | <5 min | S tickets, typo fixes, docs-only |
| Standard | 20 | 15-30 min | M and most L tickets |
| Full | 30 | 1-2 hr | XL tickets, release candidates, high-stakes |

Tech Director's triage choice is logged with rationale. Override paths exist. Mode is a tool, not a corner-cutting excuse.
