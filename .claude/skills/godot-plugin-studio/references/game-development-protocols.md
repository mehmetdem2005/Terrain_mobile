# Game Development Protocols

The protocols specific to pure Godot game development. These complement (do not replace) the v2.0 plugin protocols. The Tech Director loads these when triaging a game ticket.

Contents:
1. Game project folder structure (analog of plugin manifesto's folder template)
2. Gameplay loop architecture
3. Save system protocol
4. Scene management protocol
5. Performance budget protocol
6. Autoload discipline
7. Game-specific Phase 1.G additions

---

## 1. Game project folder structure

The plugin manifesto's folder template (in `clean-architecture-manifesto.md`) doesn't fit games. Games have characters, levels, items, world content. The studio's recommended game folder layout:

```
project_root/
├── project.godot
├── icon.png
├── README.md
│
├── scenes/                          # Top-level playable scenes
│   ├── main_menu.tscn
│   ├── game.tscn                    # Main game scene
│   ├── settings.tscn
│   └── ...
│
├── levels/                          # Level content
│   ├── level_01.tscn
│   ├── level_02.tscn
│   └── shared/                      # reusable level pieces
│
├── characters/                      # Character scenes and scripts
│   ├── player/
│   │   ├── player.tscn
│   │   ├── player.gd                # PlayerController
│   │   ├── player_state_machine.gd
│   │   └── states/
│   │       ├── idle_state.gd
│   │       ├── run_state.gd
│   │       └── jump_state.gd
│   ├── enemies/
│   │   ├── slime/
│   │   ├── ghost/
│   │   └── boss/
│   └── npcs/
│
├── items/                           # Pickups, inventory items
│   ├── definitions/                 # .tres Resource files
│   │   ├── potion_health.tres
│   │   └── sword_basic.tres
│   ├── item.gd                      # Item base class
│   └── item_pickup.tscn             # Scene for world-instance
│
├── ui/                              # In-game UI
│   ├── hud/
│   │   ├── hud.tscn
│   │   ├── hud.gd
│   │   └── health_bar.tscn
│   ├── menus/
│   │   ├── pause_menu.tscn
│   │   └── inventory_menu.tscn
│   └── widgets/                     # Reusable UI components
│
├── systems/                         # Game-wide systems (analog of plugin's core/)
│   ├── game_state/
│   │   ├── game_state.gd            # Top-level state machine
│   │   └── states/
│   ├── save_system/
│   │   ├── save_manager.gd
│   │   ├── save_data.gd             # The Resource that gets saved
│   │   └── save_migrations.gd
│   ├── audio/
│   │   ├── music_manager.gd
│   │   ├── sfx_manager.gd
│   │   └── audio_buses.tres
│   ├── input/
│   │   ├── input_manager.gd
│   │   └── input_remap.gd
│   ├── progression/
│   │   ├── achievement_manager.gd
│   │   └── quest_tracker.gd
│   └── pause/
│       └── pause_manager.gd
│
├── autoload/                        # Singletons (used sparingly!)
│   ├── signal_bus.gd                # Global event bus (if used)
│   └── (other autoloads — see autoload discipline below)
│
├── resources/                       # Shared content as Resources
│   ├── data/                        # Game data (.tres)
│   │   ├── enemies/                 # Enemy definitions
│   │   ├── items/                   # Item definitions
│   │   ├── dialogue/                # Dialogue trees
│   │   └── balance/                 # Tuning numbers
│   ├── materials/                   # Reused materials
│   ├── shaders/                     # Custom shaders
│   ├── themes/                      # UI themes
│   └── fonts/
│
├── art/                             # Visual assets
│   ├── characters/
│   ├── environment/
│   ├── effects/
│   └── ui/
│
├── audio/                           # Audio assets
│   ├── music/
│   ├── sfx/
│   └── voice/
│
├── domain/                          # Pure logic (no Godot deps if possible)
│   ├── combat/
│   │   └── damage_calculator.gd
│   ├── inventory/
│   │   └── inventory_logic.gd
│   └── procedural/
│       └── level_generator.gd
│
├── tests/                           # Test scenes and scripts
│   └── ...
│
└── addons/                          # Third-party plugins (if any)
    └── ...
```

### Folder principles for games

- **`scenes/` vs `levels/`** — `scenes/` is for top-level navigable destinations (menus, main game). `levels/` is for playable level content.
- **`characters/<type>/`** — each character type owns its scene, controller, state machine, and states. Self-contained.
- **`systems/`** — game-wide systems. Analog of plugin's `core/` but for games.
- **`autoload/`** — minimize. See autoload discipline below.
- **`resources/data/`** — game content as data. Enemies as `.tres`, not hardcoded.
- **`domain/`** — pure logic. Unit-testable without scene tree.

### Deviation from the manifesto folder template

Game projects don't have plugin.cfg; they have project.godot. They don't have `core/plugin.gd`; they have `scenes/main.tscn` or similar. They don't have `inspector/`; they have `ui/`. The manifesto's **invariants** apply (one system = one responsibility, etc.), but the **layout template** is game-shaped.

---

## 2. Gameplay loop architecture

Most games have a recognizable game loop. The studio's architecture for it:

### Core principle: separate update layers

```
Frame N:
  1. _input / _unhandled_input        — capture player intent
  2. _physics_process(delta)          — physics, character movement, collision response
  3. _process(delta)                  — non-physics updates: AI decisions, animations, UI
  4. (Godot internal: rendering)      — frame rendered

Frame N+1: repeat
```

The studio enforces:

- **Input → Game state mutation → Visual reflection.** Don't read input in `_process` if it affects physics; use `_physics_process` or input events. Don't update visuals in `_physics_process` if not strictly needed.

- **`_physics_process` for movement, `_process` for animation.** A character's position changes in `_physics_process`; its animation interpolates in `_process`.

- **No game logic in `_draw`.** `_draw` is for rendering. Don't change state.

- **Avoid `Engine.is_editor_hint()` in gameplay code.** Gameplay code shouldn't care about editor. If it does, the code probably belongs in an editor plugin instead.

### State machine pattern for player and enemies

The studio's default for character behaviors: explicit finite state machines.

```gdscript
# player.gd
@onready var state_machine: PlayerStateMachine = $StateMachine

func _physics_process(delta):
    state_machine.physics_process(delta)
```

```gdscript
# player_state_machine.gd
extends Node
class_name PlayerStateMachine

@export var initial_state: PlayerState
var current_state: PlayerState

func _ready():
    current_state = initial_state
    current_state.enter(self)

func physics_process(delta):
    var next_state = current_state.physics_process(self, delta)
    if next_state:
        current_state.exit(self)
        current_state = next_state
        current_state.enter(self)
```

```gdscript
# states/idle_state.gd
extends PlayerState
class_name IdleState

func enter(player):
    player.animation_player.play("idle")

func physics_process(player, delta) -> PlayerState:
    if Input.is_action_pressed("move_left") or Input.is_action_pressed("move_right"):
        return player.run_state
    if Input.is_action_just_pressed("jump"):
        return player.jump_state
    return null  # stay in this state
```

This pattern satisfies the manifesto invariants:
- **Invariant 1**: each state has one responsibility (idle = standing still)
- **Invariant 2**: one file = one state
- **Invariant 3**: each function does one thing (enter, exit, process)
- **Invariant 4**: states communicate via the state machine, not directly with each other
- **Invariant 5**: tuning values like speeds are exported on the player

Alternative patterns (behavior trees, hierarchical state machines, GOAP) are acceptable when justified. The default is the explicit state machine because it's debuggable and discoverable.

---

## 3. Save system protocol

Save systems are the most common source of mid-development crises in games. The studio's protocol:

### Mandatory properties of any save system

1. **Versioned schema.** Save files have a `version: int` field. Always.
2. **Migration path for every version increment.** When schema changes, write `migrate_v1_to_v2()` etc.
3. **Atomic writes.** Write to a temp file, then rename. Never write directly over the existing save (corruption risk).
4. **Backup of previous save.** Keep at least one previous save (corruption recovery).
5. **Corruption detection.** Load fails gracefully (informs player, doesn't crash).
6. **Partial state recovery.** If some fields fail to load, defaults are applied; game continues.

### Standard save flow

```
Player triggers save (manual, autosave, checkpoint)
    │
    ▼
SaveManager.save_game():
    1. Serialize current game state to a Dictionary
    2. Add version field
    3. JSON.stringify (or similar)
    4. Write to "user://save_temp.dat"
    5. Validate the write (read back, parse, compare)
    6. Move existing "user://save_main.dat" → "user://save_backup.dat"
    7. Move "user://save_temp.dat" → "user://save_main.dat"
    8. Emit save_completed signal
```

### Standard load flow

```
Game requests load
    │
    ▼
SaveManager.load_game():
    1. Try to read "user://save_main.dat"
    2. If file missing: return null (new game)
    3. If file unreadable: try "user://save_backup.dat"; if also fails, inform player
    4. Parse JSON
    5. Read version field; if missing, treat as v1 (oldest)
    6. Run migrations: v1 → v2 → v3 → ... → current
    7. Validate result against expected schema
    8. Return parsed save data OR error
```

### What MUST be in the save

The studio's checklist for save content:
- Current game state (which scene, which checkpoint)
- Player stats (level, HP, inventory)
- World state (chests opened, quests progressed, doors unlocked)
- Settings (if not stored separately)
- Timestamp + playtime
- Version

### What MUST NOT be in the save

- Pointers/references to runtime Node instances (will be invalid on load)
- Computed/derived state that can be reconstructed
- Engine state (camera positions that depend on scene structure; use logical references)

### Save Integrity Auditor's checklist

For every game ticket touching save:

1. **Roundtrip test:** save state → load state → state matches?
2. **Version test:** create save with old version, load with current version → migration runs cleanly?
3. **Corruption test:** corrupt the save file (truncate, garble bytes); load attempts gracefully?
4. **Partial test:** remove a field from a valid save; load handles the missing field?
5. **Backup test:** corrupt main save; backup loads successfully?

A save system that hasn't been tested with these five tests is not ready to ship.

---

## 4. Scene management protocol

Games transition between scenes (menus, levels, cutscenes). Bad scene management causes memory leaks, performance dips, and confused state.

### Scene transition states

Every scene transition goes through:

```
[Current Scene Running]
    │
    ▼
1. Begin transition (fade out, etc.)
    │
    ▼
2. Save transient state if needed
    │
    ▼
3. Free current scene (queue_free or scene_tree.unload_current_scene())
    │
    ▼
4. Wait for free to complete (next frame typically)
    │
    ▼
5. Load new scene (preload or ResourceLoader.load_threaded_request for large)
    │
    ▼
6. Add to scene tree
    │
    ▼
7. Restore relevant state to new scene
    │
    ▼
8. Begin reveal (fade in)
    │
    ▼
[New Scene Running]
```

### Scene Manager responsibilities

A central SceneManager (typically autoload) owns this transition. The studio's rules:

- **Don't free scenes from within the scene being freed.** Use call_deferred or a separate manager.
- **Don't `change_scene_to_file()` from within `_process` of the outgoing scene.** Defer to next frame.
- **Loading large scenes async.** Use `ResourceLoader.load_threaded_request` for scenes that take >100ms to load.
- **Loading screen for slow loads.** If the load takes more than a couple of frames, show a loading scene in between.

### Persistent vs scene-local state

Two state categories:

**Persistent (survives scene change):**
- Player inventory
- Quest progress
- World flags (chests opened, etc.)
- Settings

**Scene-local (rebuilt per scene):**
- Camera position relative to scene
- UI state of in-scene menus
- Spawned entity positions (regenerated by the scene's logic)

Persistent state lives in:
- Autoload singletons (sparingly), OR
- A persistent state Resource passed via SceneManager

Scene-local state lives in:
- The scene tree itself
- Resources owned by the scene

### Anti-pattern: state leakage via autoload

If you find yourself adding more and more autoloads to share state between scenes, the structure is degrading. The studio prefers passing state via the SceneManager or via signals emitted at scene-load completion.

---

## 5. Performance budget protocol

Games have framerate targets. The studio enforces them through budgets at Phase 1.C (Architecture) and verification at Phase 1.G (Integration).

### Per-target budgets

| Target | Framerate goal | Frame budget |
|--------|---------------|--------------|
| Desktop high-end | 60 fps (or 120/144) | 16.6 ms (8.3 / 6.9 ms) |
| Desktop mid | 60 fps | 16.6 ms |
| Mobile flagship | 60 fps | 16.6 ms |
| Mobile mid-range | 30 fps | 33.3 ms |
| Mobile low-end | 30 fps with dynamic resolution scaling | 33.3 ms |

The studio's standing rule: **the game must hit its target framerate on its target hardware**, not on the developer's machine.

### Frame budget breakdown (typical)

A 16.6 ms frame on mobile flagship typically allocates:
- ~2 ms: physics simulation
- ~1 ms: AI / game logic
- ~2 ms: animation / skinning
- ~4-6 ms: rendering (CPU side)
- ~5-7 ms: rendering (GPU side, paralleled)
- Remainder: safety margin

These are guidelines, not laws. The actual budget depends on game and platform.

### Performance gates at Phase 1.G (game tickets)

| Gate | Check |
|------|-------|
| Framerate stable on target | Framerate Auditor runs game in target scene, measures min/avg/95th percentile |
| No spike frames | Auditor identifies frames over budget; any spike >2x budget is investigated |
| Memory under target | Memory Auditor checks RSS / Godot's memory monitor |
| Load time under target | Loading Time Auditor times scene transitions |

For mobile-targeted games: thermal throttling consideration — the game should sustain framerate after 10+ minutes of play, not just at startup.

### Common game performance defects (added to defect catalog in Faz 16)

- Per-frame allocations in `_process`
- Recursive scene tree scans in `_process`
- Excessive draw calls (too many small meshes; should batch)
- Shader complexity beyond budget (especially translucent shaders)
- Audio bus count explosion
- Particle system unbounded
- Physics body count explosion

---

## 6. Autoload discipline

Godot's autoload (singleton) feature is powerful and easily abused. The studio's discipline:

### When autoload is appropriate

- Truly global services: SignalBus, SaveManager, AudioManager, GameState
- Things that exist before any scene and survive scene changes
- Things accessed from many disconnected places (where passing references would be impractical)

### When autoload is wrong

- "Manager" for a single scene's needs — should be a node in that scene
- Holding state that could live on a Resource
- Holding state for one specific gameplay feature (belongs in that feature's structure)
- Anything you'd find yourself wanting to instance twice

### Autoload audit at Phase 1.D

Before adding any autoload, ask:

1. **Does this really need to exist before the scene tree?**
2. **Is it accessed from many disconnected places?**
3. **Would scene-local nodes solve this with more clarity?**

If "yes, yes, no" — autoload is justified.
If any is "no" — restructure.

The studio's default: **start with no autoloads**. Add them only when justified. Most games can run with 3-5 well-chosen autoloads; some need more, but each one is a deliberate choice.

### Signal bus pattern

The most common autoload is a SignalBus — a global event channel.

```gdscript
# autoload/signal_bus.gd
extends Node

signal player_died
signal level_completed(level_id: String)
signal item_collected(item: Item)
signal save_requested
signal save_completed
```

**Pros:** decouples emitters and listeners; cross-scene communication.
**Cons:** signals become "fire and forget"; no clear contract about who listens.

The studio uses SignalBus for **truly global events**, not for things that have a natural owner. `player_died` is global. `enemy_health_changed` is not — it belongs to the enemy emitting it.

---

## 7. Game-specific additions to Phase 1.G

When the Pipeline Orchestrator runs Phase 1.G for a **game ticket**, additional stages activate:

| Game-stage | Check | Owner |
|-----------|-------|-------|
| G-1 | Framerate stable in target scene | Framerate Auditor |
| G-2 | Memory budget under target | Memory Auditor |
| G-3 | Loading time within budget | Loading Time Auditor |
| G-4 | Save roundtrip clean (if save touched) | Save Integrity Auditor |
| G-5 | Multiplayer state consistency (if applicable) | Multiplayer Sync Auditor |
| G-6 | Game feel acceptable (player-facing changes) | Game Feel Auditor |
| G-7 | Autoload count justified | Game Architecture Lead |
| G-8 | State machines explicit (no implicit boolean tangles) | Architectural Quality Auditor |

These run in parallel with the existing 30 stages, but only for game tickets. Pipeline duration extends accordingly: a Standard-mode game ticket may take 30-45 minutes (vs 15-30 for plugin); Full-mode game ticket may take 1.5-2.5 hours.

The user can ask for these to be skipped if the situation warrants — but the explicit override is recorded (as with any pipeline skip).

---

## Game ticket lifecycle differences from plugin tickets

Most of the v2.0 protocol applies unchanged. The differences:

| Phase | Game ticket addition |
|-------|---------------------|
| 1.A Understand | What's the player experience target? Target framerate? Target platform? |
| 1.B Discovery | Performance feasibility on target hardware (not just "does the API exist") |
| 1.C Architecture | Save schema decision (if persistent state); autoload decisions; state machine design |
| 1.D Planning | Scene tree planning; resource (data) file planning; autoload list |
| 1.E Architecture Gate | Verify autoload list is minimal; verify state machines are explicit |
| 1.F Execution | Wire-as-you-build still applies; game state machines built incrementally |
| 1.G Integration | All game-stages G-1 through G-8 above, in addition to plugin stages |

---

## When a game ticket is small

For S/M game tickets, the discipline relaxes (same as plugin tickets in Lite mode):
- No performance audit if the change is cosmetic
- No save integrity check if save isn't touched
- No game feel audit if not player-facing
- But: any change to save schema, persistent state, or core game loop always upgrades to at least Standard

---

## The studio's game-dev hill

The plugin studio's hill is "doesn't fall apart when it grows."

The game studio's hill is the same, plus: **the game must feel good for the player.**

A perfectly architected game that lags at 30 fps where it should be 60 is a failure. A perfectly architected game with confusing controls is a failure. The game must:
1. Be structurally sound (manifesto invariants)
2. Hit its performance targets
3. Feel good (Game Feel Auditor's responsibility)

The third item is harder to automate. The Game Feel Auditor's reports are qualitative — but mandatory. A game ticket that ships without a Game Feel Auditor pass is incomplete.

---

End of game development protocols. Next file: defect/pattern catalogs for game development (Faz 16).
