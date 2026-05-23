# Game Development Departments (v2.1)

The studio's original v1.0/v2.0 focus was **plugin development** — building tools that extend the Godot editor. Pure game development is different. The user is a player, not a developer. The deliverable is a game, not an addon. The concerns are framerate, save corruption, multiplayer state desync, gameplay feel — not Asset Library conformance.

v2.1 expands the studio with five new departments covering pure Godot game development. The existing 14 departments still apply to plugin work and shared concerns; the new five add game-specific specialization.

**Tech Director's triage now branches:** is this a plugin ticket (existing org structure) or a game ticket (game-dev departments)? Mixed tickets get both.

---

## Why game dev needs its own departments

Plugin development optimizes for:
- API correctness
- Editor integration
- Asset Library submission
- Compatibility with user code
- Tool ergonomics for Godot developers

Game development optimizes for:
- Framerate stability for end players
- Game feel (input responsiveness, animation polish)
- Save game robustness
- Performance scaling with content
- Player experience (not developer experience)
- Multiplayer state synchronization
- Memory budgets and asset loading

These overlap, but the specialists needed are different. A Renderer Specialist for plugins worries about Inspector theming; a Renderer Specialist for games worries about draw-call counts and post-processing budget on mobile.

---

## The five new departments

### Department 15: Gameplay Engineering

**Charter:** Build and maintain the game's playable systems. Player control, enemies, items, abilities, progression, win/loss conditions, game loops.

**Roles:**

- **Gameplay Lead** — owns the game's playable behavior overall. Coordinates gameplay specialists. Final authority on "does this feel right?"

- **Player Controller Engineer** — owns the player character's input handling, movement, state machine. Tunes feel parameters with the Gameplay Lead.

- **Enemy AI Engineer** — owns NPC behaviors, navigation, decision logic. Handles state machines, behavior trees, or whatever AI paradigm fits.

- **Combat / Interaction Engineer** — owns the mechanics of how the player interacts with the world (combat, conversation, pickups, environmental interaction).

- **Game State Engineer** — owns the high-level game state machine: title screen, in-game, paused, game-over, win, etc. Transitions, lifecycle of each state.

- **Progression Engineer** — owns leveling, unlocks, achievements, quest tracking. The systems that make players feel like they're advancing.

**Cross-cutting concerns this department handles:**
- Game feel (input latency, animation responsiveness, audio sync)
- Pacing
- Player-facing difficulty tuning
- Tutorial flow integration

### Department 16: Rendering Engineering

**Charter:** Optimize visual output. Maintain framerate. Manage draw calls, shader complexity, lighting, post-processing. **Specifically for runtime game scenes**, not editor UI.

**Roles:**

- **Rendering Lead** — owns the visual budget for the game. Approves changes that affect draw calls, fill rate, shader complexity.

- **Material / Shader Engineer** — owns custom materials and shaders for game objects. Different from plugin Shader Specialist; this one is focused on game runtime, not editor inspector tools.

- **Lighting Engineer** — owns lighting setup. Real-time vs baked decisions, light count budgets, shadow quality vs cost.

- **Post-Process Engineer** — owns the post-process stack. Glow, DoF, color grading, tonemapping. Knows what works in Forward+ vs Forward Mobile.

- **Mobile GPU Specialist** — owns mobile GPU constraints. Tile-based rendering implications, bandwidth budgets, ASTC/ETC2 trade-offs, thermal throttling awareness.

- **VFX Engineer** — owns particle systems, GPUParticles3D, screen effects, custom visual feedback for game events.

**Distinguished from plugin renderer concerns:** plugin Renderer Specialist worries about inspector theming and viewport-overlay drawing; game Rendering Lead worries about the game world rendering at 60 fps on the target hardware.

### Department 17: Physics & Simulation

**Charter:** Physics interactions, collision, character controllers, rigid bodies, navigation, area triggers. Anything where the game world "behaves" according to physical or simulation rules.

**Roles:**

- **Physics Lead** — owns the physics layer. Approves physics-system changes. Picks PhysicsServer level vs node level.

- **Collision Engineer** — owns collision shape design, collision layer/mask architecture, collision event handling. The most common bug area in games.

- **Character Controller Engineer** — owns CharacterBody3D / CharacterBody2D behaviors. Different from Player Controller Engineer (gameplay) — this one focuses on the physics-level implementation of locomotion.

- **Navigation Engineer** — owns NavigationServer, NavigationAgent, NavMesh bakes. Pathfinding budgets.

- **Simulation Engineer** — owns non-physics simulations: weather, day/night, ecosystem, economy — anything time-evolving in the world.

### Department 18: Audio Engineering

**Charter:** Sound design integration, music systems, audio mixing, dynamic audio response to gameplay.

**Roles:**

- **Audio Lead** — owns the game's audio pipeline. Approves audio bus structure, music transitions, SFX architecture.

- **SFX Implementation Engineer** — owns sound effect integration. AudioStreamPlayer placement, randomization, polyphony management.

- **Music System Engineer** — owns dynamic/adaptive music. Layered stems, transitions, state-driven music.

- **Audio Mixing Engineer** — owns the bus layout, volume curves, EQ, ducking, spatialization.

- **Voice / Dialogue Engineer** — owns spoken audio playback, lip-sync if applicable, dialogue triggering systems.

### Department 19: Game Architecture

**Charter:** Cross-cutting architectural concerns specific to games. Save system, scene transitions, autoload structure, mod/extensibility design, data-driven design (Resources for content).

**Roles:**

- **Game Architecture Lead** — owns the top-level game structure. Authority over autoload usage, scene hierarchy choices, signal bus design.

- **Save System Engineer** — owns save/load. Schema design, versioning, migration, partial-save resilience, corruption detection.

- **Scene Management Engineer** — owns scene transitions, loading screens, persistent vs scene-local state, scene tree organization.

- **Data Architecture Engineer** — owns Resources-based content (items, levels, characters as `.tres` files). Resource validation, hot-reload for development.

- **Mod / Extensibility Engineer** — owns modding API if the game supports it. Plugin loading, sandbox concerns, content discovery.

---

## Game-dev cross-cutting roles (additions to existing supervisors)

### Gameplay-side cross-cutting

- **Game Feel Auditor** — runs at every L/XL gameplay ticket. Plays the game. Reports on how it feels — input latency, animation responsiveness, audio sync. Subjective but documented.

- **Difficulty Tuner** — evaluates whether new gameplay content is appropriately difficult. Tunes parameters, doesn't write new systems.

- **Player Experience Advocate** — analogous to End-User Advocate (existing), but for players rather than developers. Reads the game's UX from a new player's eyes.

### Performance-side cross-cutting

- **Framerate Auditor** — measures framerate stability across game scenarios. Different from Performance Lead — narrowly focused on player-visible smoothness.

- **Memory Auditor** — tracks memory budgets. Asset loading, texture streaming, scene allocation. Catches leaks specific to scene lifecycle.

- **Loading Time Auditor** — measures and budgets scene load times, asset load times, first-frame time.

### Quality-side cross-cutting

- **Save Integrity Auditor** — runs save/load cycle tests, corruption simulation, version migration tests. Critical for any game with persistent state.

- **Multiplayer Sync Auditor** — for networked games. Verifies authority models, predicts desync risks, audits state replication.

---

## Mapping to existing studio roles

Some game-dev concerns map to existing studio roles with reframed scope:

| Game-dev concern | Existing role applies (with game framing) |
|-------------------|------------------------------------------|
| Asset loading errors | Crash Auditor (with scene-lifecycle context) |
| Game crashing on Android | Stability Engineer + Mobile GPU Specialist |
| Game-side architectural review | Architecture Veto Officer (same role, applied to game scenes) |
| Game code clean? | Clean Code Officer + Architectural Quality Auditor (same roles) |
| Manifesto invariants for game code | Same five invariants apply |

The studio's quality protocols are domain-agnostic. The manifesto applies whether the code is editor plugin or game runtime. New departments add the **domain expertise** for game-dev specifics.

---

## Activation rules for game tickets

Tech Director's triage flowchart now includes:

```
Is this a plugin ticket or a game ticket?

  Plugin → activate plugin-relevant departments (Tools Engineering, etc.)
  Game → activate game-dev departments + cross-cutting + manifesto

  Mixed (e.g., "build a game tool that's also useful in the editor")
    → activate both; Tech Director picks the primary
```

For **game tickets specifically**, default role activations by size:

### S game ticket (typo, parameter tweak, single-line bug fix)
- Tech Director (triage)
- Domain specialist for the area touched
- Honesty Auditor, Quality Gate Officer (always)

### M game ticket (small feature, single-system change)
- S list + Gameplay Lead OR Rendering Lead OR Physics Lead OR Audio Lead (whoever owns the area)
- Game Feel Auditor IF the change is player-facing
- Save System Engineer IF the change touches persistent state

### L game ticket (multi-system feature, new mechanic, major content)
- M list + relevant department's specialists
- Game Architecture Lead
- Framerate Auditor + Memory Auditor (always for L)
- Player Experience Advocate (if player-facing)
- All v2.0 quality protocols (Architecture Veto, Semantic Dep, Integration, etc.)

### XL game ticket (vertical slice, major system rewrite, multi-week work)
- L list + multiple department leads
- Adversarial Hunt convened
- Full Bug Hunter cohort
- Save Integrity Auditor (mandatory for any persistent-state changes)
- Loading Time Auditor (mandatory)
- 3-alternative design (Innovation Engine)
- Full pipeline mode

---

## Why this isn't just "add more roles"

The role list grew significantly (25+ new roles). The studio's role-instantiation-protocol guards against role inflation. These additions clear that bar because:

1. **Each role has a non-overlapping scope** vs the existing 80+ roles
2. **Each role is activated only for game tickets** — plugin tickets don't see them
3. **The existing studio has no game-dev specialization** — without these additions, game tickets get reviewed by plugin specialists, who give plugin-flavored advice

The role-authority-boundaries.md document is updated alongside this addition to clarify game-dev role boundaries.

---

## Game studio vs plugin studio — what stays the same

These v2.0 protocols apply equally to both domains:

- Multi-phase execution (7 phases)
- Architecture Veto at Phase 1.E
- Semantic Dependency Engine
- Integration Enforcement (wire-as-you-build)
- Deferred Work Tracker
- Clean Architecture Manifesto (5 invariants)
- Spaghetti Pattern Catalog
- Innovation Engine (3 alternatives)
- Automation Pipeline (30-stage)
- Cost-aware execution modes (Lite/Standard/Full)
- Honesty Audit
- All cross-cutting supervisors

The studio's quality discipline doesn't change. Only the specialists do.

---

## Game studio vs plugin studio — what changes

| Aspect | Plugin studio | Game studio |
|--------|--------------|-------------|
| Primary user | Godot developer using the plugin | Player playing the game |
| Asset Library submission | Mandatory consideration | N/A |
| Editor theme integration | Critical | N/A (game has own UI/theme) |
| Inspector customization | Common ticket type | Rare (only for in-editor game tools) |
| Forward Mobile renderer | Concern for editor compat | Concern for shipped game |
| Save schema | Rare (plugins may have small settings) | Critical, with migration paths |
| Framerate | Editor framerate when plugin runs | Game's runtime framerate |
| Multiplayer | Almost never | Sometimes critical |
| Mod support | N/A | Sometimes |
| Loading times | N/A | Critical |

The Tech Director's triage now considers domain when triaging. A ticket that says "make this faster" gets very different treatment in plugin context (editor responsiveness) vs game context (player-visible framerate).

---

## Adding game-dev concerns to existing protocols

The existing v2.0 protocols are updated to be domain-aware:

- **`semantic-dependency-engine.md`** — Category R-Z added in Faz 16 for game-specific dependencies (save schema changes, scene transition coupling, multiplayer state, etc.)

- **`godot-4.6.2-defect-catalog.md`** — extended in Faz 16 with 50+ game-specific defect patterns

- **`clean-architecture-manifesto.md`** — applies as-is; the folder template is plugin-shaped but the principles are universal. Game projects use a different folder template (documented in `game-folder-structure.md` in Faz 15).

- **`automation-pipeline.md`** — full-pipeline.sh remains 30 stages but stage 12 (Semantic Dependency Walk) and stage 17 (Defect Pattern Walk) walk game-specific catalogs for game tickets.

---

## How the user invokes game mode

The user's request signals domain. The studio reads the signal:

- "Build a Godot game where..." → game mode
- "Build a Godot plugin for..." → plugin mode
- "I need an editor tool that..." → plugin mode
- "Help me debug my game's save system" → game mode
- "Why does my game stutter on Android?" → game mode
- "Why does my plugin not load on Android editor?" → plugin mode

For ambiguous requests, the studio asks one clarifying question:

> "Quick clarification — is this for a game you're shipping (game mode) or a Godot editor tool you're building (plugin mode)? It changes which specialists I bring in."

---

## Department interactions in game mode

```
Gameplay Engineering
    ├── needs ─→ Physics & Simulation (for physical behaviors)
    ├── needs ─→ Audio Engineering (for combat sounds, etc.)
    ├── needs ─→ Rendering Engineering (for VFX, animation polish)
    └── needs ─→ Game Architecture (for save integration, state mgmt)

Rendering Engineering
    ├── coordinates with ─→ Performance (existing dept, for budgets)
    └── coordinates with ─→ Mobile GPU Specialist (mobile target)

Game Architecture
    ├── owns ─→ Save System Engineer (most critical sub-role)
    ├── owns ─→ Scene Management
    └── advised by ─→ Architecture Veto Officer (cross-domain)

Audio Engineering
    └── relatively independent; coordinates with Gameplay for timing
```

---

## Closing note

This expansion makes the studio dual-domain: it can build plugins AND it can build games. The quality bar is identical (manifesto, invariants, AAA discipline). The expertise differs.

The next two phases (15 and 16) flesh out the game-side protocols and catalogs. After v2.1 closes, the studio is ready for game development tickets at the same maturity level as plugin tickets.
