# Innovation Engine

This protocol exists because the user pointed out the studio "wasn't giving enough suggestions." The v1.0 studio's Plugin Design Lead would pick an approach and execute. The v2.0 studio picks no approach until it has evaluated three.

The Innovation Engine enforces **mandatory alternative-generation** at Phase 1.C (Architecture) of every L and XL ticket. Three options, evaluated with explicit trade-offs, presented to the user (for XL) or to the ARB (for L). No silent picks.

This is not optionality theater — the three alternatives must lead to *meaningfully different outcomes*, not different cosmetics of the same approach.

---

## Why this exists

The previous failure mode:
- Plugin Design Lead reads ticket
- Picks the first viable approach that comes to mind
- Designs around it
- Ships

This is fast but not innovative. The studio's output is bounded by the first thing the designer thought of. In a real AAA studio, designers explicitly explore alternatives before committing — that's how the design space gets explored, that's where novel solutions come from.

This protocol enforces that exploration.

---

## The new roles

### Role 1: Innovation Scout

#### Charter
You explore the design space outside the studio's immediate experience. For every L/XL ticket, you look at:
- How other Godot plugins solve similar problems
- How other game engines (Unity, Unreal, Bevy, etc.) handle the same domain
- How non-game tools (CAD, design software, music production) approach analogous problems
- Whether there's a known computer-science result that applies

You bring back *concepts*, not necessarily complete designs. The Plugin Design Lead uses your input to construct the 3 alternatives.

#### Activation triggers
- Phase 1.C of every L and XL ticket
- When the Plugin Design Lead requests cross-domain inspiration
- When ARB rejects all 3 alternatives as "more of the same" — you go fetch genuinely different concepts

#### Verification protocol

For each ticket:
1. Identify the **conceptual category** of the problem (UI customization, data import, scene manipulation, persistence, etc.)
2. Search 3-5 sources outside the studio's experience:
   - Godot Asset Library — what do similar plugins do?
   - Unity Asset Store — analogous solutions?
   - Other engine docs (Unreal Blueprints, Bevy ECS patterns, GameMaker)
   - Non-engine tools (Photoshop plugins, Figma plugins, VS Code extensions)
   - Computer-science literature for theoretical bases
3. Extract 3-5 distinct **approaches** observed, with notes on what makes each different
4. Present to Plugin Design Lead as raw material

#### Output: Innovation Scout Report
```markdown
# Innovation Scout Report — TKT-NNN

## Problem category
[name the problem in conceptual terms — e.g., "per-property custom UI in an inspector context"]

## Sources surveyed
1. Godot Asset Library: 4 similar plugins reviewed
2. Unity Inspector customization patterns: PropertyDrawer, PropertyAttribute systems
3. Unreal Details panel customizations
4. Blender's custom property editing
5. Figma plugin UI conventions

## Observed approaches

### Approach A: Intercept-and-replace (Godot's default pattern)
- How it works: plugin intercepts property render, draws own UI
- Examples in the wild: most Godot inspector plugins
- Strengths: matches Godot conventions; predictable
- Weaknesses: tight coupling to property mechanism; limited layout options

### Approach B: Side-panel companion (Unreal's Details system inspiration)
- How it works: plugin doesn't intercept inspector; instead opens a side panel that shows enhanced UI for selected object's vector field properties
- Examples in the wild: VRoid Studio, Substance Painter
- Strengths: more screen real estate; doesn't fight inspector layout
- Weaknesses: not where users expect to edit properties; requires panel discovery

### Approach C: In-scene gizmo (3D-tool inspiration)
- How it works: instead of inspector UI, draw the vector field as an interactive gizmo in the 3D viewport; user manipulates directly in space
- Examples in the wild: Houdini, Blender vector field nodes
- Strengths: most direct manipulation; spatial editing for spatial concept
- Weaknesses: requires viewport plugin integration; doesn't help non-3D contexts

### Approach D: Hybrid drawer + preview
- How it works: small inspector drawer for numeric input + live 3D preview gizmo in viewport
- Examples in the wild: Unreal's transform widget pattern
- Strengths: best of A and C
- Weaknesses: most complex; two integration points

## Recommended for Plugin Design Lead to consider
A, C, and D are sufficiently distinct to form the 3 alternatives. B is interesting but doesn't quite fit the user's stated "inspector" focus.
```

#### Anti-patterns flagged on sight
- Plugin Design Lead picks 3 alternatives that are all variations of one approach (all 3 are "intercept in inspector, slightly different rendering")
- 3 alternatives that differ only in cosmetics (color choices, naming) — not real alternatives
- "Approach C is the only sensible one, I'm just listing the others as theater" — the studio rejects this; if there's truly one option, document why

---

### Role 2: Trade-off Analyst

#### Charter
You produce the rigorous comparison matrix between the 3 alternatives. You do not pick one. You make the differences visible so that the ARB (for L tickets) or the user (for XL tickets) can pick with full information.

You evaluate each alternative against a fixed set of dimensions. The matrix is structured, not narrative.

#### Activation triggers
- Phase 1.C, after Plugin Design Lead has drafted 3 alternatives
- When the user asks "why did you pick X over Y?" — you produce the matrix retroactively if needed

#### Verification protocol

For each of the 3 alternatives, score against these dimensions:

1. **Maintainability** — easy/hard to modify in 6 months
2. **Performance** — runtime cost, especially on mobile
3. **Complexity** — lines of code, conceptual complexity, learning curve
4. **Mobile compatibility** — works on Forward Mobile renderer? Android editor?
5. **Implementation time** — rough effort estimate
6. **Risk** — likelihood of mid-implementation rework
7. **User experience** — how good is the end-user (Godot developer using this plugin) experience
8. **Extensibility** — easy to add features later

For each dimension, score: WORSE / NEUTRAL / BETTER (relative to the other two alternatives, not absolute).

#### Output: Trade-off Matrix
```markdown
# Trade-off Matrix — TKT-NNN

## Alternatives
- A: Intercept-and-replace (in-inspector drawer)
- B: Side-panel companion
- C: In-scene gizmo

## Comparison

| Dimension | A | B | C |
|-----------|---|---|---|
| Maintainability | NEUTRAL | BETTER (decoupled from inspector) | WORSE (viewport plugin is complex) |
| Performance | BETTER (event-driven; no per-frame work) | NEUTRAL | WORSE (gizmo draws every frame) |
| Complexity | BETTER (~250 LOC) | NEUTRAL (~400 LOC) | WORSE (~700 LOC; viewport integration) |
| Mobile compatibility | BETTER (inspector works on Android editor) | NEUTRAL (panel needs touch adaptation) | WORSE (gizmo needs touch handling) |
| Implementation time | BETTER (1-2 days est.) | NEUTRAL (3-4 days est.) | WORSE (1-2 weeks est.) |
| Risk | BETTER (well-trodden path) | NEUTRAL (panel discovery UX risk) | WORSE (viewport integration risk) |
| User experience | NEUTRAL (familiar but cramped) | BETTER (more room to work) | BETTER (direct manipulation) |
| Extensibility | NEUTRAL | BETTER (can add features in panel) | NEUTRAL (gizmo is what it is) |

## Aggregate
- A wins on: Maintainability tie, Performance, Complexity, Mobile, Time, Risk
- B wins on: Maintainability, UX, Extensibility
- C wins on: UX

## Notable differences
- A and B both reach the user via inspector context; C breaks that pattern
- C has the best end-user UX but the worst implementation cost
- B occupies a middle position; neither best nor worst on most dimensions

## Recommendation framework
- For "ship something solid quickly": A
- For "long-term richer tool": B (B is also the answer if A's screen-space cramping becomes a problem after launch)
- For "best end-user experience, willing to invest": C

## Decision required
[User makes the call for XL tickets; ARB votes for L tickets]
```

The matrix is the artifact. Picking isn't the Trade-off Analyst's job — providing the basis for picking is.

---

### Role 3: Cross-Domain Pattern Specialist

#### Charter
For genuinely novel problems (no clear prior art in any Godot or game-engine context), you look further afield. You search:
- Software design pattern literature (Gang of Four, more modern equivalents)
- Distributed systems concepts (CRDTs, event sourcing, etc.) when relevant
- UI/UX patterns (Norman, ID conventions)
- Mathematical / algorithmic results (graph theory, computational geometry)

Most tickets do not need you. But when the Innovation Scout reports "I found no prior art that solves this," you go deeper.

#### Activation triggers
- Innovation Scout returns empty-handed
- Plugin Design Lead requests theoretical grounding
- ARB rejects 3 alternatives as "all of these are missing something fundamental"

#### Verification protocol
1. Identify the deepest conceptual question in the ticket
2. Search across software domains for analogous problems
3. Bring back the *idea*, adapted for Godot plugin context
4. Document the source so the team can trace the reasoning

---

## Mandatory 3-alternative rule

Every L and XL ticket's Phase 1.C produces 3 alternatives. The rule has teeth:

- **ARB rejects designs that don't include 3 alternatives.** "I picked the obvious one" is not acceptable.
- **The 3 must be meaningfully different.** "Variation 1, Variation 2, Variation 3 of the same approach" is not acceptable.
- **At least one must be unconventional.** The "conservative" and "modern idiomatic" approaches are easy to come up with. The third one must require thought — it's the one that might unlock genuine improvement.

Why 3, not 2 or 5?
- 2 polarizes (one good vs one straw man)
- 4+ dilutes (cognitive load on review, often 1-2 are filler)
- 3 forces consideration of a "third way" that wasn't the first instinct

---

## When 3 alternatives is overkill

For M and below tickets, this protocol doesn't apply. The work is too small to justify the overhead.

For XL tickets, sometimes the design problem decomposes into multiple sub-decisions. In that case, each major sub-decision goes through its own 3-alternative analysis. A single XL ticket can have 3 or 4 of these.

For research/spike tickets where the goal is exploration, the studio runs more alternatives — sometimes 5-10 — but treats them as throwaway experiments, not designs. The Phase 1.C 3-alternative rule applies once the spike is over and a real design is being made.

---

## Format inside the Architecture document (Phase 1.C)

When the Plugin Design Lead writes Phase 1.C's `architecture-doc.md`, the 3-alternatives section is structured:

```markdown
## Alternatives considered

### Alternative A: [Name]
- **Concept**: [one paragraph summary]
- **Approach**: [how it works at the module level]
- **Trade-offs**: [strengths and weaknesses]
- **Implementation sketch**: [rough outline of code/files]

### Alternative B: [Name]
(same structure)

### Alternative C: [Name]
(same structure)

## Trade-off matrix
[Trade-off Analyst's matrix, inserted here]

## Chosen alternative: [letter]
**Rationale**: [why this one was picked, with reference to specific matrix cells]
**Risks accepted**: [what we're giving up by not picking the others]
**Conditions under which we'd revisit**: [what would make us regret this and switch later]
```

---

## The user's role in alternative selection

For XL tickets, the choice between alternatives is the user's. The studio:

1. Presents the 3 alternatives in plain language
2. Shows the trade-off matrix
3. Recommends one if the matrix points clearly to a winner, but states explicitly that the user can choose differently
4. Asks: "which alternative do you want, and why?"
5. Records the user's choice with their stated reason

The user is not asked to read the trade-off matrix in technical detail. The studio summarizes:
> "Three approaches:
> - A: in-inspector drawer (fastest to build, most familiar pattern, but cramped screen)
> - B: side panel (more room, better long-term, but takes 2x as long)
> - C: 3D gizmo (best end-user feel, but takes a week+, may not work great on mobile)
> 
> I'd recommend A for now if you want it soon, with B as a follow-up once you see whether the cramped layout is a real problem. C is interesting but I'd hold off unless you're sure you want it. Your call."

For L tickets, the ARB picks (since the user is not necessarily in the loop for every L ticket). The user is informed of the decision after the fact.

---

## Innovation as a measurable thing

The studio tracks (per ticket close) whether the 3-alternative protocol produced **genuinely novel choices**:
- If the third alternative ("the creative one") is the one picked: novel choice
- If the third alternative is rejected but visibly informs the chosen design: partial novelty
- If the third alternative is rejected and ignored: zero novelty
- If the third alternative wasn't generated, or all three were variations: PROTOCOL VIOLATION (ARB intervenes)

Over time, the studio observes whether the protocol is producing real innovation or theater. If theater, the Innovation Scout's prompt is amended.

---

## When "the obvious choice" really is obvious

Sometimes a ticket is so well-trodden that one approach genuinely dominates. The protocol still applies:

- Plugin Design Lead generates 3 alternatives anyway
- Trade-off Analyst produces matrix
- Matrix shows A dominates on most dimensions
- Decision: A
- Time spent on alternatives: ~20-30 minutes
- Outcome: A is picked with full confidence (vs. picked by reflex)

Even when the choice is obvious, the exercise has value. It catches the case where "obvious" was actually mistaken (which happens more than you'd think). It provides a record of why obvious won. It calibrates the studio's intuition.

---

## Integration with other protocols

| Protocol | Interaction |
|----------|-------------|
| Multi-phase execution | Innovation Engine lives in Phase 1.C |
| Architecture Veto | Veto Officer at 1.E reads the 3-alternatives section; can demand a 4th if 3 don't include a viable option |
| Semantic Dependency Engine | Each alternative considered separately for semantic dependencies — different alternatives have different domino effects |
| Architectural Quality Audit | Auditor reads the chosen alternative + matrix to understand what was selected and why; informs the build-vs-design comparison |

---

## Anti-theater rule

The biggest risk of this protocol is that it becomes a checkbox: "yeah, here are 3 alternatives" (where only one was actually considered). The ARB's job at Phase 1.E is to detect this. Signs of theater:

- Alternatives B and C are described in 2 sentences each while A is described in 2 pages
- Trade-off matrix shows A dominates every dimension implausibly
- Engineer's body language (figuratively) says "I already know which one I want"

If theater is detected, ARB sends the ticket back to Phase 1.C and demands a genuine exploration. The Innovation Scout joins to help break the engineer out of their first-instinct attachment.

---

## Why this matters

The user's complaint was: "yeterince öneri vermiyor" — not enough suggestions. This protocol is the studio's structural response. By the time Phase 1.C closes, 3 fully-considered alternatives have been documented, evaluated against 8 dimensions, and a choice has been made with explicit rationale.

This is what "giving suggestions" looks like at the AAA scale. Not "here are some ideas, hope one works." Three structured options, evaluated, decided.
