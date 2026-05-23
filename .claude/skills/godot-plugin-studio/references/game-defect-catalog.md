# Godot 4 Game Development Defect & Pattern Catalog (v2.1)

The studio's curated catalog of recognized bug patterns and architectural smells **specific to pure Godot game development** — not plugin work. Walked by the Defect Pattern Specialist (with help from the new game-dev specialists from Faz 14) for every L/XL game ticket.

Where `godot-4.6.2-defect-catalog.md` covers editor-time plugin defects (lifecycle, inspector, undo/redo), this catalog covers runtime game defects (gameplay loop, scene tree management, physics, multiplayer, save/load, mobile game performance).

The catalog is organized by concern. Currently 100+ entries across 14 categories.

---

## How this catalog complements the plugin catalog

| Concern | Plugin catalog (64 patterns) | Game catalog (this file, 100+ patterns) |
|---------|------------------------------|-----------------------------------------|
| Lifecycle | `_enter_tree`/`_exit_tree` on EditorPlugin | `_ready`/`_exit_tree` on gameplay nodes, scene transitions |
| Signals | Editor-bound signals, inspector refreshes | Gameplay event bus, multiplayer RPC, save/load triggers |
| Resources | Custom Resource for editor data | Runtime resource loading, async load, streaming |
| Mobile | Editor on Android | Game on Android/iOS — touch input, batteries, thermal |
| State | Editor mutation via UndoRedo | Game state machines, save corruption, multiplayer desync |
| Performance | _process in editor (rare) | _process in game (constant); frame budget critical |

A team building both plugins and games will reference both. A team building only games starts here.

---

## Category GA — Gameplay loop defects

### GAME-DEF-001: Frame-rate dependent gameplay
**Pattern**: Physics or movement applied without delta multiplication
```gdscript
# Bad
func _process(delta):
    position.x += 5.0   # ← runs at 144 FPS = 5x speed of 30 FPS player

# Good
func _process(delta):
    position.x += 5.0 * delta
```
**Detect**: Look for `position +=`, `velocity =`, rotation changes inside `_process` without `delta` multiplication.
**Fix**: Multiply by `delta`, OR use `_physics_process` which has fixed delta.
**Severity**: P1 (gameplay feel breaks on different machines)

### GAME-DEF-002: Physics in _process
**Pattern**: `move_and_slide()`, `move_and_collide()`, or other physics-dependent calls in `_process` instead of `_physics_process`
**Bug**: Inconsistent collision behavior, jitter, missed collisions at high frame rates
**Detect**: Scan `_process` bodies for physics API calls.
**Fix**: Move physics to `_physics_process`.
**Severity**: P1

### GAME-DEF-003: Logic in _physics_process that should be _process
**Pattern**: UI updates, camera lerping, or visual-only smoothing in `_physics_process`
**Bug**: Choppy visuals on machines with high frame rate / low physics tick rate; wasted CPU
**Detect**: `_physics_process` bodies — look for UI updates, visual interpolation, sound triggers
**Fix**: Move visual/UI logic to `_process`; keep `_physics_process` for physics state only
**Severity**: P3

### GAME-DEF-004: Variable-step timer using _process accumulation
**Pattern**: `time_since_X += delta; if time_since_X > THRESHOLD:` — but loses precision over long runs
**Bug**: Drift over time; events fire late after hours of play
**Detect**: Float accumulators that grow unboundedly in `_process`
**Fix**: Use `Timer` node, OR reset accumulator on each fire (`time_since_X = fmod(time_since_X, THRESHOLD)`)
**Severity**: P3

### GAME-DEF-005: Pause not honored
**Pattern**: Custom timer or logic that runs even when `get_tree().paused = true`
**Bug**: Gameplay continues during pause menu
**Detect**: Nodes with `process_mode = PROCESS_MODE_ALWAYS` that shouldn't be; or custom timers that don't check pause state
**Fix**: Set appropriate `process_mode`; or check `get_tree().paused` in custom loops
**Severity**: P2

### GAME-DEF-006: Game logic in UI script
**Pattern**: HUD/menu script doing game-state mutation (damage, score updates as side effects of UI events)
**Bug**: Game state lives in two places; refactoring HUD breaks gameplay
**Detect**: UI scripts that mutate Player, GameState, World, etc. — should emit signals instead
**Fix**: UI emits user-action signals; game systems listen and decide
**Severity**: P2 (architectural; per Clean Architecture Manifesto Invariant 4)

### GAME-DEF-007: Hard-coded difficulty/balance
**Pattern**: Enemy HP, damage, drop rates as literal numbers scattered across code
**Bug**: Cannot tune without recompile; designers can't iterate
**Detect**: `grep` for numeric constants in gameplay code
**Fix**: Move to `BalanceData.tres` resource; reference from gameplay code
**Severity**: P3 (Manifesto Invariant 5 violation)

### GAME-DEF-008: Player input polled every frame instead of event-driven
**Pattern**: `if Input.is_action_pressed("jump"):` checked every `_process` for one-shot actions
**Bug**: Multiple triggers in one button press; missed inputs on slow frames
**Detect**: `Input.is_action_pressed` for actions that should be `is_action_just_pressed`
**Fix**: Use `is_action_just_pressed` for one-shot; `_input` for event-driven; only poll for "held" states
**Severity**: P2

---

## Category GB — Scene tree management defects

### GAME-DEF-009: queue_free called on still-active reference
**Pattern**: Node A holds reference to Node B; B is queue_free'd; A accesses B next frame
**Bug**: "Previously freed object" runtime error
**Detect**: Cross-scene references held in variables; lack of `is_instance_valid` checks
**Fix**: Use `is_instance_valid(b)` before access; OR `b = null` on free; OR use signals for one-way notification
**Severity**: P1

### GAME-DEF-010: Scene change without freeing previous
**Pattern**: `get_tree().change_scene_to_packed(new_scene)` called repeatedly without cleanup of background-loaded scenes
**Bug**: Memory leak; eventually crash
**Detect**: Scene change calls — verify what happens to the old scene (Godot 4 frees automatically for change_scene; not for manual add_child workflows)
**Fix**: For manual workflows, explicitly queue_free the old scene before adding new
**Severity**: P2

### GAME-DEF-011: get_node with absolute path
**Pattern**: `$"/root/World/Player"` or `get_node("/root/World/Player")`
**Bug**: Path breaks when scene structure changes; brittle
**Detect**: Strings starting with `/root/` in node queries
**Fix**: Use `@onready var player = $Player` (relative) OR groups (`get_tree().get_first_node_in_group("player")`) OR scene-specific references via @export
**Severity**: P3

### GAME-DEF-012: Singleton autoload abuse
**Pattern**: Every system as autoload singleton — `GameManager`, `AudioManager`, `UIManager`, `SaveManager`, `PlayerManager`, `EventBus`, etc.
**Bug**: Hidden coupling; everything depends on everything; testing impossible
**Detect**: Count autoloads in `project.godot`; if more than ~3-5, review whether each is truly global
**Fix**: Keep autoloads for genuine globals (audio bus, settings); use dependency injection or signals for rest
**Severity**: P2 (Manifesto Invariant 4 violation)

### GAME-DEF-013: Deep scene nesting for organization
**Pattern**: `World/Level/Section/Area/Subarea/Entity/Sprite` — scene structure used as folder structure
**Bug**: Slow `get_node` lookups; brittle paths; hard to navigate in editor
**Detect**: Scenes with depth > 5 levels
**Fix**: Flatten using groups, layers (CanvasLayer for UI), or instanced sub-scenes with their own roots
**Severity**: P3

### GAME-DEF-014: Owner-less node addition
**Pattern**: `add_child(node)` without setting `node.owner = self` for nodes that should be saved with the scene
**Bug**: Editor doesn't show the node in scene tree; not saved
**Detect**: `add_child` calls in `_ready` of `@tool` scripts or scene-construction code
**Fix**: After `add_child`, set `owner` for editor-persistent nodes
**Severity**: P2 (tool/editor scenes only)

### GAME-DEF-015: Scene reparenting breaks transforms
**Pattern**: Move a Node3D from one parent to another without compensating transforms
**Bug**: Node jumps to wrong world position
**Detect**: `reparent()` calls; or `remove_child` + `add_child` patterns
**Fix**: Use `reparent(new_parent, keep_global_transform=true)` (default in Godot 4)
**Severity**: P2

### GAME-DEF-016: Process callbacks on inactive nodes
**Pattern**: Hundreds of nodes all running `_process` even when inactive (e.g., enemies offscreen)
**Bug**: CPU wasted; frame rate suffers
**Detect**: Profile reveals many `_process` callbacks on inactive entities
**Fix**: `set_process(false)` on inactive nodes; OR `set_physics_process(false)`; OR use VisibilityNotifier/VisibleOnScreenNotifier3D
**Severity**: P2

---

## Category GC — Physics defects

### GAME-DEF-017: CharacterBody2D/3D used for non-character entities
**Pattern**: Bullets, decorations, NPCs all using CharacterBody for movement
**Bug**: Overkill; CharacterBody has expensive collision resolution; RigidBody or AnimatableBody often appropriate
**Detect**: `CharacterBody2D`/`CharacterBody3D` count vs. node count
**Fix**: Use the right body for the role — CharacterBody for player/character; RigidBody for physics-driven; AnimatableBody for moving platforms; Area for triggers
**Severity**: P3

### GAME-DEF-018: Direct global_position write on physics body
**Pattern**: `rigid_body.global_position = teleport_target` without using `PhysicsServer` or `body.set_global_transform`
**Bug**: Causes physics tunneling; collisions missed; "stuck in wall"
**Detect**: Direct position assignments on RigidBody/CharacterBody
**Fix**: For teleport: `body.global_position = target; body.linear_velocity = Vector3.ZERO; PhysicsServer3D.body_set_state(...)` ; OR use AnimatableBody for kinematic motion
**Severity**: P2

### GAME-DEF-019: move_and_slide returns ignored
**Pattern**: `move_and_slide()` called without checking `is_on_floor()`, `is_on_wall()`, `get_slide_collision()`
**Bug**: Movement continues into walls without reaction; or jumps trigger mid-air
**Detect**: `move_and_slide()` calls — check whether collision state is queried after
**Fix**: After `move_and_slide`, check collision state and react (`if is_on_floor():` for gravity reset)
**Severity**: P2

### GAME-DEF-020: Collision layer/mask not configured
**Pattern**: Default collision layer/mask (1/1); everything collides with everything
**Bug**: Bullets hit projectiles; enemies stuck on each other; debug nightmare
**Detect**: Project settings → Layer Names → Physics — empty? Layer assignments — all default?
**Fix**: Name your layers (Player, Enemy, World, Projectile, Trigger); assign appropriately
**Severity**: P3 (works initially, breaks at scale)

### GAME-DEF-021: Raycast every frame for line-of-sight
**Pattern**: 100+ enemies each raycasting to player every `_physics_process`
**Bug**: CPU bottleneck
**Detect**: Profile `_physics_process`; count raycasts per frame
**Fix**: Stagger raycasts (only N enemies per frame check); OR use distance-first check; OR use VisibleOnScreenNotifier
**Severity**: P2 (performance)

### GAME-DEF-022: Area3D/Area2D body_entered without filtering
**Pattern**: Area's `body_entered` signal handler runs heavy logic without checking what entered
**Bug**: Trigger fires for unintended bodies (e.g., player's own bullets re-trigger their own area)
**Detect**: `body_entered` connect — does handler check `body.is_in_group("player")` or similar?
**Fix**: Filter early in handler; OR use collision layer to limit what enters
**Severity**: P2

### GAME-DEF-023: PhysicsBody static_body misused for moving platform
**Pattern**: `StaticBody3D` script moves its `position` to make a moving platform
**Bug**: Physics doesn't know it's moving; player on top doesn't get carried
**Detect**: `StaticBody*` with position-mutation script
**Fix**: Use `AnimatableBody3D` (kinematic body — physics-aware movement)
**Severity**: P1 (broken platform gameplay)

---

## Category GD — Save / load defects

### GAME-DEF-024: Node reference stored in save data
**Pattern**: Save file contains a NodePath that won't resolve after scene reload
**Bug**: Loaded game has broken references
**Detect**: Save schema — any `NodePath`, `Node`, or `Object` fields?
**Fix**: Save IDs/names; resolve to nodes after load
**Severity**: P1

### GAME-DEF-025: Save schema version missing
**Pattern**: Save file has no version field; future schema changes will silently corrupt old saves
**Bug**: Update breaks saves; users lose progress
**Detect**: Save dict has no `"version"` or `"schema_version"` key
**Fix**: Always include version; write migration logic per version increment
**Severity**: P1

### GAME-DEF-026: Save during gameplay transition
**Pattern**: Save triggered during scene change, mid-animation, or mid-physics-step
**Bug**: Saved state is inconsistent (player position before transition, inventory after)
**Detect**: Save calls — when is the trigger? Stable moments only?
**Fix**: Save only at safe moments: world checkpoints, menu open, level complete; defer if in transition
**Severity**: P2

### GAME-DEF-027: Save file path uses absolute or res://
**Pattern**: `FileAccess.open("res://save.dat", FileAccess.WRITE)` — `res://` is read-only in exported games
**Bug**: Save fails on exported game; works in editor (deceptive)
**Detect**: Save paths — anything not in `user://`?
**Fix**: Always use `user://` for save data
**Severity**: P0 (data loss in shipping build)

### GAME-DEF-028: JSON save with custom Resources
**Pattern**: Trying to JSON-serialize a custom Resource subclass
**Bug**: Loses class info; load reconstructs as Dictionary, not original class
**Detect**: Save code: `JSON.stringify(some_resource)` where resource is non-trivial
**Fix**: Use `ResourceSaver.save()` for Resources; JSON for simple Dictionary state; or build a to_dict/from_dict round-trip
**Severity**: P1

### GAME-DEF-029: No save corruption recovery
**Pattern**: Save file gets corrupted (game crash mid-write); next load crashes the game
**Bug**: Unrecoverable; user must delete save
**Detect**: Save logic — atomic write? Backup of previous save?
**Fix**: Write to `save.dat.tmp`, then rename to `save.dat`; keep `save.dat.bak` from previous successful save
**Severity**: P1

### GAME-DEF-030: Save bloat — entire world serialized
**Pattern**: Save dumps every entity in the world, including procedural foliage, particles, transient effects
**Bug**: Save file megabytes; slow load
**Detect**: Save file size on small playtest — does it grow with playtime?
**Fix**: Save only persistent state (player progress, world flags, key entities); regenerate procedural content from seed
**Severity**: P2

---

## Category GE — State machine defects

### GAME-DEF-031: Implicit state via booleans
**Pattern**: `is_jumping`, `is_falling`, `is_attacking`, `is_dead`, `is_stunned` — many flags
**Bug**: Invalid combinations possible (jumping AND attacking AND dead?); branching nightmare
**Detect**: 4+ boolean state flags on one entity
**Fix**: Explicit state machine (enum + transition function); only one state at a time
**Severity**: P2 (Spaghetti catalog S-008: Hidden State Machine)

### GAME-DEF-032: State change without exit logic
**Pattern**: Changing state by setting a variable without running cleanup of previous state
**Bug**: Stale state lingers (animation still playing, particles still emitting)
**Detect**: State variable assignments — is there an exit/enter framework?
**Fix**: `change_state(new_state)` function that calls `_exit_state(old_state)` then `_enter_state(new_state)`
**Severity**: P2

### GAME-DEF-033: AI behavior tree without timeouts
**Pattern**: Behavior tree state "ChasingPlayer" with no timeout; enemy chases forever if player escapes
**Bug**: Enemies frozen in pursuit; broken gameplay
**Detect**: BT states — does each have a timeout or exit condition?
**Fix**: Every active state has at least one exit condition (timeout, condition met, condition failed)
**Severity**: P2

### GAME-DEF-034: Animation state desync with logic state
**Pattern**: `state = State.IDLE` but animation is still "Attacking"
**Bug**: Visual lies about logical state
**Detect**: State change without corresponding `animation_player.play(...)` call
**Fix**: Animation triggers tied to state enter (centralized in `_enter_state`)
**Severity**: P2

---

## Category GF — Input handling defects

### GAME-DEF-035: Input not consumed by UI
**Pattern**: Player can move/attack while clicking buttons in HUD
**Bug**: Accidental gameplay actions during menu interaction
**Detect**: Action triggers in gameplay code without checking `get_viewport().gui_get_focus_owner()` or similar
**Fix**: Use `_unhandled_input` for gameplay (UI consumes input first); or check UI focus state
**Severity**: P2

### GAME-DEF-036: Touch input not supported
**Pattern**: Mobile build but only keyboard/mouse input mapped
**Bug**: Game unplayable on mobile
**Detect**: Mobile target + no touch in InputMap
**Fix**: Add touch actions; OR use TouchScreenButton overlay; OR remap automatically when `OS.has_feature("mobile")`
**Severity**: P1 (mobile)

### GAME-DEF-037: Controller/gamepad assumed but not detected
**Pattern**: Game shows "Press A to start" but checks keyboard `enter`
**Bug**: Controller users confused; keyboard users see wrong prompt
**Detect**: Hardcoded input prompts; no detection of `Input.is_joy_known(0)`
**Fix**: Detect device on last input received; swap prompts accordingly
**Severity**: P3

### GAME-DEF-038: Input action triggered during scene transition
**Pattern**: Player presses jump just as scene changes; jump fires in new scene
**Bug**: Unexpected actions in new context
**Detect**: Input handling enabled during transitions
**Fix**: Disable input processing during transitions (set `process_mode` or guard with `is_transitioning` flag)
**Severity**: P3

### GAME-DEF-039: Mouse capture not released
**Pattern**: `Input.mouse_mode = MOUSE_MODE_CAPTURED` set on game start; never released for menu
**Bug**: User can't click menu buttons
**Detect**: Mouse mode changes — is there a release path?
**Fix**: Release on Esc, menu open, scene change to menu
**Severity**: P2

---

## Category GG — Multiplayer / RPC defects

### GAME-DEF-040: @rpc("any_peer") with no authority check
**Pattern**: Function accepts RPC from any peer but doesn't validate the caller
**Bug**: Cheating — any peer can trigger admin actions
**Detect**: `@rpc("any_peer")` annotations — does function check `multiplayer.get_remote_sender_id()`?
**Fix**: Check sender ID; only act if sender is authorized
**Severity**: P0 (security/cheating)

### GAME-DEF-041: State synced every frame
**Pattern**: `MultiplayerSynchronizer` syncing every frame including for distant/inactive entities
**Bug**: Bandwidth waste; latency on important sync
**Detect**: Sync configuration on entities; replication interval = 0 (every frame) for everything?
**Fix**: Use interval; sync important state every frame, cosmetic less frequently; cull by distance
**Severity**: P2

### GAME-DEF-042: Client-authoritative position
**Pattern**: Each client tells the server "my position is X" — trusted
**Bug**: Speedhack / teleport cheat possible
**Detect**: Position sync direction — client → server unchecked?
**Fix**: Server-authoritative; client sends input; server simulates; reconcile client prediction
**Severity**: P1 (competitive games)

### GAME-DEF-043: RPC argument type mismatch
**Pattern**: RPC sends a `Vector3`, receiver typed as `Vector2` (typo or refactor)
**Bug**: Runtime error or silent corruption
**Detect**: Compare `@rpc` function signature with caller arguments
**Fix**: Type-check both sides; use strict typing
**Severity**: P1

### GAME-DEF-044: No latency compensation
**Pattern**: Multiplayer game without client-side prediction
**Bug**: Movement feels unresponsive at any non-trivial ping
**Detect**: Multiplayer game with `multiplayer.is_server()` checks but no prediction layer
**Fix**: Implement client-side prediction + server reconciliation (Godot doesn't include this OOTB; pattern is well-documented)
**Severity**: P1 (action games)

### GAME-DEF-045: Disconnection not handled gracefully
**Pattern**: Peer disconnects; game crashes or freezes
**Bug**: Bad UX; ungraceful exit
**Detect**: `multiplayer.peer_disconnected` signal — connected to handler?
**Fix**: Handle disconnect: pause/end game, show message, return to menu
**Severity**: P2

---

## Category GH — Resource and asset defects

### GAME-DEF-046: load() in hot path
**Pattern**: `load("res://bullet.tscn")` called inside `_process` or every shot
**Bug**: Disk I/O every call; stuttering
**Detect**: `load()` calls in hot path
**Fix**: `const BULLET = preload("res://bullet.tscn")` at file scope
**Severity**: P1

### GAME-DEF-047: preload of large resource at startup
**Pattern**: `const HUGE_LEVEL = preload("res://level_5.tscn")` in a script that always loads
**Bug**: Startup time penalty; memory used for resources not yet needed
**Detect**: Const preloads of MB-sized resources; profile startup
**Fix**: Use `ResourceLoader.load_threaded_request()` for large resources; show loading screen
**Severity**: P2

### GAME-DEF-048: Texture not power-of-two on mobile
**Pattern**: 1234x567 texture used on mobile target
**Bug**: Wasted VRAM (rounded up); slow on some GPUs
**Detect**: Texture dimensions on mobile build
**Fix**: Power-of-two textures (1024x512, 2048x1024); enable mipmaps
**Severity**: P3

### GAME-DEF-049: Audio not streamed for music
**Pattern**: Long music track loaded as `AudioStreamWAV` instead of `AudioStreamOggVorbis` or `AudioStreamMP3` with streaming
**Bug**: Entire track in memory; slow load
**Detect**: Import settings on music files
**Fix**: Use compressed format with `loop` enabled; verify "Loop" setting
**Severity**: P3

### GAME-DEF-050: Resource shared mutation
**Pattern**: Multiple instances reference the same Resource and one mutates it
**Bug**: All instances change unexpectedly (Resources are shared by reference)
**Detect**: Resources assigned via `@export var data: MyResource`; instances mutating `data.field = X`
**Fix**: `duplicate(true)` on assignment for instance-private state; OR use a non-Resource type for mutable per-instance state
**Severity**: P1

---

## Category GI — Mobile game performance defects

### GAME-DEF-051: Renderer not set to Mobile
**Pattern**: Mobile target but project using "Forward+" renderer
**Bug**: Editor allows features that fail on device; or runs poorly
**Detect**: `project.godot` → `rendering/renderer/rendering_method.mobile` field; should be `mobile`
**Fix**: Set mobile renderer; review materials/effects for compatibility
**Severity**: P1

### GAME-DEF-052: Real-time shadows on every light
**Pattern**: All lights have `shadow_enabled = true` on mobile
**Bug**: Severe frame rate drop
**Detect**: Light count × shadow_enabled count
**Fix**: Bake shadows where possible; limit real-time shadow casters; use lower shadow resolution
**Severity**: P1

### GAME-DEF-053: Particles GPU-heavy on mobile
**Pattern**: GPUParticles3D with 10k+ particles on mobile
**Bug**: Frame rate collapse; thermal throttling
**Detect**: Particle counts on mobile target
**Fix**: Use CPUParticles where simpler; reduce counts on mobile via dynamic quality; LOD for particle effects
**Severity**: P2

### GAME-DEF-054: Post-processing stack on mobile
**Pattern**: WorldEnvironment with glow, SSAO, SSR, DOF all enabled on mobile target
**Bug**: Game runs at 15 FPS
**Detect**: WorldEnvironment settings on mobile build
**Fix**: Disable expensive post-fx on mobile; provide mobile WorldEnvironment variant
**Severity**: P1

### GAME-DEF-055: Always-on screen wake / no battery awareness
**Pattern**: Mobile game runs at 60 FPS in pause menu
**Bug**: Battery drain
**Detect**: `_process` running during pause / menus
**Fix**: Lower FPS cap on menus (`Engine.max_fps = 30` for menus, restore on gameplay); detect background and pause completely
**Severity**: P2

### GAME-DEF-056: Touch hit areas too small
**Pattern**: UI buttons smaller than ~44dp on mobile
**Bug**: Hard to tap accurately
**Detect**: Button `custom_minimum_size` on mobile target
**Fix**: Minimum 44dp (scale by `DisplayServer.screen_get_dpi`); add invisible padding to small icons
**Severity**: P2

### GAME-DEF-057: Thermal/sustained-performance not considered
**Pattern**: Game runs flat-out at 60 FPS; phone throttles after 10 minutes
**Bug**: Frame rate drops mid-session
**Detect**: Sustained playtests on mobile target
**Fix**: Cap FPS at 30-40 for mobile; reduce work during idle moments; adaptive quality
**Severity**: P2

---

## Category GJ — Audio defects

### GAME-DEF-058: Audio overlap on rapid trigger
**Pattern**: "Hit" sound triggered every frame on continuous collision; audio overlaps to chaos
**Bug**: Audio mess; performance hit
**Detect**: AudioStreamPlayer triggered without throttle in repeating contexts
**Fix**: Throttle (minimum time between plays); OR use one-shot with rate limit; OR audio bus polyphony limit
**Severity**: P2

### GAME-DEF-059: Music not stopped before new track
**Pattern**: New scene starts; new music plays; old music still playing
**Bug**: Two tracks overlapping
**Detect**: Music transitions — does old music get explicit stop?
**Fix**: `previous_music.stop()` before `new_music.play()`; OR fade out + fade in
**Severity**: P2

### GAME-DEF-060: Distance attenuation not configured
**Pattern**: 3D positional audio without `unit_size`/`max_distance` configured
**Bug**: Audio heard from across the map; or barely audible up close
**Detect**: AudioStreamPlayer3D nodes — check attenuation settings
**Fix**: Tune `unit_size` and `max_distance` per sound type
**Severity**: P3

### GAME-DEF-061: Audio bus volume not respecting user preference
**Pattern**: Game has volume slider in options but ignores it for some sounds
**Bug**: Player thinks they muted music; SFX still loud
**Detect**: Audio not routed through named buses (Master/Music/SFX/UI)
**Fix**: Route all audio through buses; slider adjusts bus volume; persisted in save
**Severity**: P3

---

## Category GK — Rendering defects (Game-runtime)

### GAME-DEF-062: Materials not shared
**Pattern**: 100 enemies each with their own `StandardMaterial3D` instance (duplicated by mistake)
**Bug**: 100 unique materials → 100 shader compilations / state changes per frame
**Detect**: Material count grossly exceeds visually distinct material types
**Fix**: Share materials across instances; use per-instance uniforms (or shader instance variables) for unique values
**Severity**: P2

### GAME-DEF-063: Visible OpaquePass items used for transparent
**Pattern**: Sprite with alpha channel using opaque material
**Bug**: Hard edges; halos around transparent regions
**Detect**: Transparent assets with opaque material
**Fix**: Set material's `transparency` to `Alpha` or use alpha-tested mode
**Severity**: P3

### GAME-DEF-064: Camera frustum culling bypassed
**Pattern**: Every entity uses `visible = true` always; no LOD/culling
**Bug**: Drawing offscreen entities
**Detect**: Profile reveals draw calls on offscreen entities
**Fix**: VisibleOnScreenNotifier for activation gating; use LOD; let engine cull what it can
**Severity**: P2

### GAME-DEF-065: Shader compiled at first use mid-gameplay
**Pattern**: Player encounters new enemy; shader compiles; hitch
**Bug**: Frame stall on first appearance of any shader variant
**Detect**: Hitches during gameplay on new effects
**Fix**: Pre-warm shaders at load (instantiate hidden examples of each material at startup)
**Severity**: P2

### GAME-DEF-066: Reflection probes not baked
**Pattern**: Real-time reflection probes used on mobile or in performance-sensitive scenes
**Bug**: Heavy CPU/GPU per frame
**Detect**: ReflectionProbe `update_mode = ALWAYS` on mobile
**Fix**: Bake reflections (`update_mode = ONCE` and update on relevant events only)
**Severity**: P2

---

## Category GL — Memory and lifecycle defects

### GAME-DEF-067: Tween outlives target
**Pattern**: `create_tween().tween_property(node, ...)` and node freed before tween completes
**Bug**: "Previously freed object"
**Detect**: Tween targets — node lifetime vs tween lifetime
**Fix**: Bind tween to target (`node.create_tween()` makes it bound) OR kill tween on target free
**Severity**: P2 (same pattern as plugin DEF-PATTERN-008)

### GAME-DEF-068: Signal connection persists after target free
**Pattern**: A connects to B's signal; B freed; A still tries to disconnect later
**Bug**: Error on disconnect; or signal still fires into freed B
**Detect**: Signal connections not cleaned up in matching free paths
**Fix**: Use `Object.signal.connect(callable)` (Godot 4 syntax) which is auto-cleared when target freed; OR explicit `is_connected()` check before disconnect
**Severity**: P2

### GAME-DEF-069: Array of nodes not pruned
**Pattern**: `var enemies: Array[Node3D] = []` — enemies added but freed-references not removed
**Bug**: Iterating array hits null references
**Detect**: Arrays of nodes — is there a pruning step?
**Fix**: Use groups (`get_tree().get_nodes_in_group("enemies")` — automatically fresh) OR clean on `tree_exited` signal
**Severity**: P2

### GAME-DEF-070: Dictionary keyed by node reference
**Pattern**: `var damage_dealt: Dictionary = {}; damage_dealt[enemy] = 50`
**Bug**: Freed enemy keys persist; memory leak; lookup fails
**Detect**: Dictionaries with Object keys
**Fix**: Key by ID/name; OR clean on `tree_exited`
**Severity**: P2

### GAME-DEF-071: Singleton state never reset
**Pattern**: `GameManager` autoload accumulates state over a session; new game still has old data
**Bug**: State leaks between game sessions
**Detect**: Autoload state — explicit reset method? Called on new game?
**Fix**: Provide and call `reset()` method on game-over / new-game
**Severity**: P2

---

## Category GM — Concurrency and timing defects

### GAME-DEF-072: await on signal during free
**Pattern**: `await some_node.signal_x` — but `some_node` freed before signal fires
**Bug**: Coroutine hangs forever
**Detect**: `await` calls — target lifetime vs await scope
**Fix**: Race with timeout (`await signal_x` vs `get_tree().create_timer(N).timeout`)
**Severity**: P2

### GAME-DEF-073: call_deferred chain incorrect order
**Pattern**: `call_deferred("free_old")` then `call_deferred("setup_new")` — order assumption may break
**Bug**: New setup runs before old is freed; corrupted state
**Detect**: Multiple `call_deferred` in same scope
**Fix**: Chain explicitly: `call_deferred("free_old_then_setup_new")` as single deferred function
**Severity**: P2

### GAME-DEF-074: Frame-counter modulo for periodic events
**Pattern**: `if Engine.get_frames_drawn() % 60 == 0:` — assumes 60 FPS for "once per second"
**Bug**: At 30 FPS runs every 2 seconds; at 144 FPS runs many times per second
**Detect**: `get_frames_drawn() %` patterns
**Fix**: Use Timer node, or time-based accumulator: `time_accum += delta; if time_accum > 1.0: time_accum = 0; fire()`
**Severity**: P2

### GAME-DEF-075: Race on signal emit during list iteration
**Pattern**: Iterating list of enemies; signal connected such that enemy.die() removes from list
**Bug**: Iteration breaks; some enemies missed
**Detect**: Loop modifies the collection it iterates
**Fix**: Iterate a copy: `for enemy in enemies.duplicate(): ...`; OR defer removal to after loop
**Severity**: P2

---

## Category GN — Architectural smells (game-specific)

### GAME-ARCH-001: "GameManager knows everything" autoload
Same as plugin S-004 (Manager God Object), but specifically in game context. The `GameManager` becomes the place where everything lives because it's globally accessible.
**Fix**: Separate concerns — GameSession (current run state), GameSettings (persisted prefs), GameClock (pause/time scale), EventBus (signals). Each as autoload if truly needed; otherwise instanced.

### GAME-ARCH-002: Scene as procedural code
Scene tree assembled entirely in code (`add_child` chains in `_ready`); no `.tscn` files used.
**Bug**: Designer can't edit; previews don't work; merge conflicts in code
**Fix**: Use `.tscn` for structure; code for behavior

### GAME-ARCH-003: Tightly coupled gameplay-UI
Player's `take_damage()` directly calls `HUD.update_health_bar()`.
**Bug**: Can't change HUD without touching player code; can't have multiple HUDs (e.g., minimap)
**Fix**: Player emits `damage_taken` signal; HUD listens. (Manifesto Invariant 4)

### GAME-ARCH-004: Hardcoded scene paths everywhere
`change_scene_to_file("res://scenes/level_1.tscn")` literally in 12 places.
**Bug**: Rename one scene → 12 file edits
**Fix**: Central `SceneRouter` with named transitions; `SceneRouter.go_to_level(1)`

### GAME-ARCH-005: Inheritance over composition for entities
`Enemy` extends `Character` extends `Entity` extends `Node3D`; each level adds methods.
**Bug**: Diamond problems; can't mix behaviors (flying + shooting?)
**Fix**: Composition — entity is a Node3D with attached component nodes (Movement, Health, Combat, AI)

### GAME-ARCH-006: World state in node properties
Game-relevant state (player position, inventory) lives in node properties; lose them on scene change
**Bug**: Scene transition loses progress
**Fix**: Separate persistent state (in dedicated state node / autoload) from view nodes

### GAME-ARCH-007: "Damage system" as method chain
`player.take_damage(amount).apply_armor(armor).check_invincibility().notify_listeners()`
**Bug**: Fluent API hides side effects; hard to reason about
**Fix**: Damage as data: `damage_event = DamageEvent.new(...)`; pipeline applies modifiers; result determined; listeners notified by signal

---

## Walking the catalog for game tickets

For every L/XL game-dev ticket:

1. **Identify which categories are relevant** to this ticket's scope
2. **For each relevant category, walk every pattern**
3. **For each pattern**, run the `Detect` instruction (grep, code review question, profiler observation)
4. **Log results** to ticket audit trail: PASS / MATCH / N/A per pattern
5. **For matches**, raise blockers with severity baseline (often P0/P1 in game-dev — frame rate, save data, security)

Typical walk time:
- L game ticket: 20-30 minutes (more than plugin walks; game patterns are usually subtler)
- XL game ticket: 45-90 minutes; combined with Adversarial Hunt

---

## Extending the catalog

This catalog will grow. Mobile-specific patterns, multiplayer, 2D-vs-3D variants — there are gaps. The Studio Knowledge Curator + Game Architecture Lead promote new entries as the studio encounters them in real game tickets.

The first version (this document) is the seed. Each game ticket that surfaces a novel pattern earns the studio a new catalog entry.
