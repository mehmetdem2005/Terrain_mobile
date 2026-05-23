# Semantic Dependency Engine

This is the system that catches the "domino effect" — the implicit dependencies between code and concepts that grep cannot find. It is the studio's answer to the failure mode where adding one thing silently breaks five others.

This protocol runs in Phase 1.G (Integration) of every L and XL ticket. It is mandatory; no ticket reaches Quality Gate without a clean semantic dependency audit.

---

## Why grep is not enough

A grep-based impact analysis (the syntactic layer in `impact-analysis-protocol.md`) catches:
- Function X was renamed → find all callers
- Property Y's type changed → find all assignments
- File Z was moved → find all `preload` paths

But grep misses the semantic dependencies:

- You added a diff texture import → the matching normal texture should also be considered
- You added a `velocity` property → its `velocity_changed` signal probably should also exist
- You changed how scenes are saved → existing user `.tscn` files need migration thought
- You added a custom hint → its `_property_can_revert` / `_property_get_revert` pair is implied
- You introduced a state machine → entry/exit transitions, invalid-transition handling, save/load, undo all implied
- You changed a public method's behavior → documentation, examples, tutorials, and tests all need review

None of these is findable by grep. They are findable only by a role that **thinks about the concept**, not just the symbol.

The Semantic Dependency Engineer is that role.

---

## The new role: Semantic Dependency Engineer

### Charter
You hunt the implicit dependencies. When the studio introduces, modifies, or removes any concept (not just symbol), you ensure the related concepts are also addressed. You consult the Semantic Dependency Pattern Catalog (in this document) and apply every rule that fits. Your authority is to raise blockers that cannot be silently dismissed.

You are not the engineer; you do not implement the dependent changes. You identify them and ensure they are either addressed in this ticket or formally deferred to the Deferred Work Tracker (no item is "forgotten").

### Activation triggers
- Phase 1.G of every L and XL ticket
- Any new public API surface introduced mid-ticket
- Any concept that maps to a pattern in the catalog
- Tools Engineer asks "do I need to worry about X?" — you answer authoritatively

### Verification protocol — the 7-question audit

For every new/changed concept in the ticket, ask these 7 questions. Each answer is logged to the audit trail.

#### Q1: Does this concept have a paired counterpart?
Examples: `add` → `remove`; `connect` → `disconnect`; `init` → `cleanup`; diff texture → normal texture; signal emit → signal listen; serialization → deserialization.
If yes: is the counterpart addressed?

#### Q2: Are other items in the same category affected?
Examples: if you change one texture's resolution, are other textures in the same pipeline still consistent? If you add a property hint to one Vector3 export, should other Vector3 exports in the same plugin get the same treatment? If you introduce a new menu item, is the menu's overall organization still coherent?
If yes: which ones and how?

#### Q3: Is a contract being changed?
Examples: function signature, return type, signal parameters, file format, user-visible behavior, persistence schema.
If yes: who depends on the old contract? Documentation? Tests? Examples? User-saved data? Other plugins?

#### Q4: Is there a lifecycle counterpart?
Examples: `_enter_tree` ↔ `_exit_tree`; resource load ↔ resource unload; subscribe ↔ unsubscribe; allocate ↔ free; cache ↔ invalidate; lock ↔ unlock; transaction begin ↔ commit/rollback.
If yes: is the counterpart symmetric?

#### Q5: Are there data structures that carry context for this concept?
Examples: if you add a `velocity` property, does any state-serialization struct need a new field? If you add a custom resource, does any cache or registry need awareness? If you add a setting, does any save/load path need extension?
If yes: list each and verify.

#### Q6: Is visual or behavioral consistency at stake?
Examples: hi-res diff with lo-res normal map = visual break. A signal that emits at frame N with a listener that reads at frame N+1 = behavioral break. A drawer that uses theme colors but a sibling drawer that uses hardcoded colors = inconsistency.
If yes: identify and address.

#### Q7: Is the user's mental model affected?
Examples: you renamed something the user has been calling X for a year. You changed the order of fields in the inspector. You moved a setting from one menu to another. The code is "correct" but the user is now confused.
If yes: documentation update + migration note + (sometimes) explicit user notification.

### Output: per-concept audit entries
```markdown
## Concept: vector_field_inspector — new EditorInspectorPlugin

Q1 (paired counterpart): 
  - add_inspector_plugin / remove_inspector_plugin pair: addressed in plugin.gd:24, 47
Q2 (same category):
  - Two other Vector3 inspectors exist; consistency: theme integration matches, undo flow matches
Q3 (contract change):
  - No public API; internal change
Q4 (lifecycle):
  - _enter_tree connects 3 signals; _exit_tree disconnects all 3; symmetric
  - Inspector plugin instance is stored and freed on exit
Q5 (data context):
  - No persistence schema affected
Q6 (visual consistency):
  - Drawer uses EditorInterface theme; matches sibling drawers
Q7 (user mental model):
  - New behavior; documented in README under "Vector Field Inspector" section
```

### Voice
Concrete, evidence-led, exhaustive. You name specific files, line numbers, and concepts.

### Cross-role relationships
- Reports to: Tech Director
- Subpoenes: API Verification Specialist (when a question becomes "does X exist"), Signal System Specialist (for signal lifecycle), Inspector / Dock / Importer specialists (domain-specific dependencies)
- Hands off to: Integration Engineer (who verifies the wiring is actually correct)
- Forwards to: Deferred Work Tracker (any item deferred is logged here)

---

## Semantic Dependency Pattern Catalog

This is the heart of the system. 100+ rules covering the dominoes that fire when specific concepts change.

The catalog is organized by **trigger** — "if you do X, consider these Y". When a ticket touches a trigger, the Semantic Dependency Engineer walks every rule under that trigger.

### A. Plugin lifecycle patterns

**A1. add_* / remove_* symmetry**
- Trigger: any `add_inspector_plugin`, `add_control_to_dock`, `add_custom_type`, `add_autoload_singleton`, `add_import_plugin`, `add_export_plugin`, `add_tool_menu_item`, `add_translation_parser_plugin`, `add_undo_redo_inspector_hook_callback`
- Implied: matching `remove_*` in `_exit_tree`
- Implied: reference to the added object stored so it can be removed
- Implied: queue_free or proper cleanup of the removed object (otherwise leak)

**A2. _enter_tree / _exit_tree**
- Trigger: any work in `_enter_tree`
- Implied: corresponding cleanup in `_exit_tree`
- Implied: idempotency (what if enable fires twice?)
- Implied: partial-init recovery (what if `_enter_tree` fails halfway?)

**A3. Plugin disable mid-action**
- Trigger: plugin maintains transient state during user action (drag in progress, edit in progress)
- Implied: `_disable_plugin` cancels in-flight action gracefully
- Implied: undo stack is left in a consistent state
- Implied: no half-applied changes persist

**A4. Plugin reload (script edit)**
- Trigger: @tool script changes while editor running
- Implied: state survives reload or is re-initialized
- Implied: dock controls re-attach
- Implied: signals re-connect

### B. Signal patterns

**B1. connect / disconnect symmetry**
- Trigger: any `signal.connect()` call
- Implied: matching `signal.disconnect()` (unless CONNECT_ONE_SHOT or documented lifetime guarantee)
- Implied: `is_connected()` guard if connect path can fire twice

**B2. Signal emit / listen**
- Trigger: any new custom signal defined
- Implied: at least one emitter exists
- Implied: at least one listener exists (if not, signal is dead code)
- Implied: signal name reflects past-tense event ("changed", not "change")

**B3. Signal parameter changes**
- Trigger: parameters of an existing signal change
- Implied: every connect site is updated
- Implied: every emit site is updated
- Implied: documentation reflects new signature

**B4. await signal**
- Trigger: code does `await some_signal`
- Implied: signal is guaranteed to emit (otherwise deadlock)
- Implied: the awaiting function's caller handles the coroutine nature
- Implied: cancellation path if signal never fires

### C. Inspector patterns

**C1. Custom drawer for property**
- Trigger: `_parse_property` returns true (intercepts a property)
- Implied: drawer commits via UndoRedo
- Implied: drawer responds to refresh
- Implied: drawer disposes cleanly when inspector reflows
- Implied: drawer respects editor theme
- Implied: drawer's keyboard tab order makes sense

**C2. @export with property hint**
- Trigger: new `@export` annotation with a hint
- Implied: hint value is valid for the type (PROPERTY_HINT_RANGE only for numerics, etc.)
- Implied: default value is sensible
- Implied: revert behavior: `_property_can_revert` and `_property_get_revert` if non-default revert needed
- Implied: serialization survives (default `@export` does, but custom serialization paths need awareness)

**C3. @export_custom with custom hint string**
- Trigger: `@export_custom` with a non-built-in hint
- Implied: matching `EditorInspectorPlugin` exists to interpret the hint
- Implied: hint string format documented
- Implied: graceful fallback if the inspector plugin isn't loaded

**C4. Inspector category / group**
- Trigger: `@export_category` / `@export_group` / `@export_subgroup` added
- Implied: consistency with other properties (don't leave some grouped and others orphaned)
- Implied: group names are translatable (`tr()` wrapped if localization in scope)

### D. Resource patterns

**D1. Custom Resource subclass**
- Trigger: `extends Resource` with `class_name`
- Implied: `_init` parameters allow zero-arg construction (resource loader needs this)
- Implied: all exported properties survive `.tres` save/load roundtrip
- Implied: no Node references (Resources outlive Nodes; references will dangle)
- Implied: version field for migration if schema may change
- Implied: `duplicate(true)` semantics considered if Resource will be duplicated

**D2. Resource format change**
- Trigger: existing custom Resource adds/removes/renames a property
- Implied: migration logic for existing `.tres` files
- Implied: `_get_property_list` or `_set` override if backward compat needed
- Implied: version bump in plugin

**D3. ResourceSaver / ResourceLoader paths**
- Trigger: code that saves or loads `.tres` files
- Implied: path validation (no `..` traversal)
- Implied: `res://` for plugin assets, `user://` for user data
- Implied: load failure handling (file missing, corrupt, wrong type)

**D4. Custom Resource registered via class_name**
- Trigger: `class_name` declaration on a Resource
- Implied: name does not collide with built-in Godot class
- Implied: name follows PascalCase
- Implied: name is unique within the project

### E. Texture and visual asset patterns

**E1. Diff texture added/changed**
- Trigger: any diffuse / albedo / color texture
- Implied: matching normal map at compatible resolution
- Implied: matching roughness map if PBR
- Implied: matching AO map if PBR
- Implied: all maps share the same UV layout
- Implied: all maps use compatible compression formats for the target platform

**E2. Texture resolution change**
- Trigger: a texture's resolution changes
- Implied: matching maps (normal, roughness, AO) at same resolution
- Implied: mip chain regenerated
- Implied: import settings consistent across the set
- Implied: target platform considerations (mobile: smaller; desktop: can be larger)

**E3. Texture compression format change**
- Trigger: change to ETC2, ASTC, BPTC, S3TC, uncompressed
- Implied: target platform supports the format
- Implied: matching maps in the set use the same format
- Implied: import settings reflect the change

**E4. Texture coordinate space change**
- Trigger: UV layout changes; texture origin (top-left vs bottom-left) changes
- Implied: all sampling code reviewed
- Implied: matching maps re-aligned

**E5. Shader-bound texture**
- Trigger: texture is sampled in a shader
- Implied: shader uniform name matches code-side binding
- Implied: format compatibility (sRGB vs linear)
- Implied: filter mode consistent with intent (nearest for pixel art, linear for normal maps)

### F. Shader patterns

**F1. New shader uniform**
- Trigger: shader code declares a new uniform
- Implied: code-side `set_shader_parameter` calls for the uniform
- Implied: default value if uniform may be unset
- Implied: documentation in shader header comment

**F2. Shader render mode**
- Trigger: change to shader_type or render_mode line
- Implied: ShaderMaterial properties compatible
- Implied: target renderer (Forward+, Forward Mobile, Compatibility) supports the mode

**F3. Shader uses derivatives (dFdx, dFdy)**
- Trigger: shader contains dFdx, dFdy, fwidth
- Implied: NOT compatible with Forward Mobile renderer's subpass tile rendering
- Implied: fallback shader for mobile OR explicit "desktop only"

**F4. Shader compute shader**
- Trigger: compute shader used
- Implied: NOT available on Forward Mobile renderer (limited)
- Implied: NOT available on Compatibility renderer
- Implied: fallback or explicit Forward+ only

### G. Node and scene patterns

**G1. Custom node type via add_custom_type**
- Trigger: `add_custom_type(name, base, script, icon)`
- Implied: icon is 16x16 PNG, two-color, recognizable
- Implied: base class is correct (e.g., extending Node3D, not Node, if needed in 3D)
- Implied: matching `remove_custom_type(name)` in `_exit_tree`
- Implied: name doesn't collide with built-in or other plugin's custom types

**G2. Scene tree modification from plugin**
- Trigger: plugin adds/removes nodes in user's scene
- Implied: UndoRedo through `EditorUndoRedoManager`
- Implied: `EditorInterface.get_edited_scene_root()` used, NOT `get_tree()`
- Implied: respects user's selection (don't unselect / change selection silently)

**G3. @onready var**
- Trigger: `@onready var x = $Path`
- Implied: path is valid at `_ready` time
- Implied: path uses correct node names (typo-safe via `%UniqueName` if applicable)
- Implied: variable is null-checked if path can be missing

### H. Animation and tween patterns

**H1. Tween creation**
- Trigger: `create_tween()` or `get_tree().create_tween()`
- Implied: tween reference stored if you need to kill it later
- Implied: `kill()` on plugin disable if tween is mid-flight
- Implied: tween cleanup when target node freed (use bound tweens)

**H2. AnimationPlayer animation**
- Trigger: new animation added or modified
- Implied: animation library consistency
- Implied: track paths still valid (renames break)
- Implied: blend times preserved if previously tuned

### I. Input handling patterns

**I1. _input vs _unhandled_input**
- Trigger: plugin handles input
- Implied: correct callback chosen (`_unhandled_input` usually for game-style)
- Implied: `accept_event()` called to prevent propagation
- Implied: input action exists in InputMap (or graceful absence handling)

**I2. Mouse-only interaction**
- Trigger: right-click context menu, hover tooltip, scroll wheel
- Implied: Android editor: no equivalent, document or provide alternative
- Implied: keyboard accessible alternative for accessibility

**I3. Custom InputAction**
- Trigger: plugin defines/uses a custom InputAction
- Implied: action exists in project's InputMap
- Implied: graceful fallback if missing
- Implied: documentation tells user to add the action

### J. Save / load and persistence patterns

**J1. Persistence schema change**
- Trigger: any save format change (config file, .tres, custom JSON, etc.)
- Implied: version field in the format
- Implied: backward-compat read path
- Implied: forward-compat (if user opens new format in old plugin: graceful refusal)
- Implied: migration documented

**J2. Plugin settings**
- Trigger: plugin stores settings (EditorSettings, project settings, .cfg file)
- Implied: defaults for missing settings
- Implied: settings UI matches stored keys
- Implied: settings keys are namespaced (e.g., `my_plugin/setting_x`, not just `setting_x`)

**J3. User data path**
- Trigger: plugin writes to `user://`
- Implied: subdirectory under plugin namespace, not bare `user://`
- Implied: error handling on disk-full, permission-denied
- Implied: data versioned for plugin updates

### K. UI and theme patterns

**K1. Editor theme colors**
- Trigger: plugin UI sets colors
- Implied: pulled from `EditorInterface.get_editor_theme()`, not hardcoded
- Implied: works with user's custom themes
- Implied: works in dark and light themes if Godot supports both

**K2. Icon usage**
- Trigger: plugin uses an icon
- Implied: 16x16 size
- Implied: matches Godot icon style (two-color, semantic)
- Implied: SVG preferred over raster
- Implied: theme-aware (light icon for dark theme, etc., if needed)

**K3. Control focus mode**
- Trigger: plugin adds focusable controls
- Implied: `focus_mode` set appropriately
- Implied: tab order is logical
- Implied: focus visible (use editor theme's focus style, don't hide it)

**K4. Tooltip text**
- Trigger: plugin sets tooltip
- Implied: tooltip is translatable (`tr()`)
- Implied: tooltip is informative (not a restatement of the label)
- Implied: alternative for touch (Android editor has no hover)

### L. UndoRedo patterns

**L1. Any mutating action**
- Trigger: user action that changes scene, resource, or persistent state
- Implied: `EditorUndoRedoManager` action created
- Implied: matching do/undo method or property pairs
- Implied: action name is human-readable (appears in Edit menu)
- Implied: action commits even on error path (or rolls back fully)

**L2. Drag-style interaction**
- Trigger: user drags a value (slider, knob, drag bar)
- Implied: undo records only the final value, not every interim frame
- Implied: drag-cancel (ESC, focus loss) restores original
- Implied: ARM (action records merging) considered for grouped drags

**L3. Multi-property action**
- Trigger: one user action changes multiple properties
- Implied: single UndoRedo action wraps all changes
- Implied: undo restores all properties together, not piecewise

### M. Mobile and Android editor patterns

**M1. Plugin runs in Android editor**
- Trigger: plugin will load in Godot Android Editor
- Implied: touch-friendly hit targets (≥44px)
- Implied: no right-click required
- Implied: no keyboard shortcut required
- Implied: works in compressed dock layout

**M2. Plugin uses Forward Mobile renderer**
- Trigger: any rendering code
- Implied: no SDFGI, limited glow/DoF
- Implied: HDR values respected (R10G10B10A2 precision)
- Implied: no compute shaders (or fallback)

**M3. Texture for mobile target**
- Trigger: texture used on mobile
- Implied: ETC2 or ASTC compression
- Implied: appropriate resolution (1K-2K usually, not 4K)
- Implied: mip chain enabled

### N. Performance patterns

**N1. _process or _physics_process**
- Trigger: per-frame callback added
- Implied: work scaled by delta
- Implied: early-out conditions for inactive state
- Implied: budget check (Performance Engineer)
- Implied: editor-only behavior gated by `Engine.is_editor_hint()`

**N2. Per-frame allocation**
- Trigger: hot path allocates (Dictionary.new, Array literal, String concat)
- Implied: cache/reuse where possible
- Implied: allocation moved out of hot path if not necessary

**N3. Linear scene tree scan**
- Trigger: `get_tree().get_nodes_in_group()` or recursive `get_children()` in hot path
- Implied: cache results when group membership is stable
- Implied: subscribe to group changes instead of polling

### O. Security and file I/O patterns

**O1. File read from path**
- Trigger: `FileAccess.open` for read
- Implied: path validated (no `..`, scoped to expected directory)
- Implied: error handling (file missing, permission denied)
- Implied: encoding considered (UTF-8 default, but be explicit if other)

**O2. File write to path**
- Trigger: `FileAccess.open` for write
- Implied: path is in `user://` (for user data) or in plugin's `res://addons/<name>/`
- Implied: directory exists or is created
- Implied: write failure handling

**O3. Resource load from user-supplied path**
- Trigger: `ResourceLoader.load(user_input)` or `load(user_input)`
- Implied: path is sanitized
- Implied: type check on loaded resource
- Implied: do NOT load .gd or .gdshader from untrusted source (executes code)

### P. Internationalization patterns

**P1. User-visible string**
- Trigger: string appears in plugin UI
- Implied: wrapped in `tr()`
- Implied: extracted to translation file
- Implied: not concatenated mid-sentence (breaks translation in many languages)

**P2. Date / number / unit formatting**
- Trigger: plugin formats dates, numbers, currency, units
- Implied: locale-aware formatting
- Implied: documented assumption if locale is fixed

### Q. Tutorial / documentation patterns

**Q1. New public API**
- Trigger: any new public method, signal, or property
- Implied: README section added/updated
- Implied: example code in tutorial (for XL tickets)
- Implied: documented signature, parameters, return value, side effects

**Q2. Existing API behavior change**
- Trigger: public API behavior changes (even if signature stays)
- Implied: CHANGELOG entry
- Implied: migration note if user code may be affected
- Implied: deprecation if removing a method (don't just remove)

### R. Testing patterns

**R1. New behavior**
- Trigger: any new user-visible feature
- Implied: at least one test scenario covering it
- Implied: test scenario is automatable where possible (`godot --check-only`, smoke run)
- Implied: edge cases enumerated by Edge Case Hunter

**R2. Bug fix**
- Trigger: ticket fixes a reported bug
- Implied: regression test added that would have caught the bug
- Implied: test included in standard test run

### S. Build, packaging, and distribution patterns

**S1. New file added to plugin**
- Trigger: new file in `addons/<plugin>/`
- Implied: file is referenced from somewhere (no orphan files)
- Implied: if a script, parses cleanly
- Implied: included in version control (no `.gitignore` exclusion)

**S2. plugin.cfg version bump**
- Trigger: code change merits a version bump
- Implied: SemVer rules (major for breaking, minor for new feature, patch for fix)
- Implied: CHANGELOG entry
- Implied: Asset Library re-submission if applicable

**S3. License header**
- Trigger: new file added
- Implied: license header matches plugin's overall license
- Implied: third-party code attribution preserved

### T. Multiplayer / RPC patterns

**T1. @rpc annotation**
- Trigger: function annotated with @rpc
- Implied: rpc mode is correct (any_peer vs authority)
- Implied: call_local flag set if needed
- Implied: parameter types are RPC-safe (Variant-serializable)

**T2. MultiplayerSpawner / MultiplayerSynchronizer**
- Trigger: plugin interacts with multiplayer
- Implied: authority model documented
- Implied: spawn/despawn paths symmetric

---

## How the engineer uses the catalog

For every concept introduced or changed in the ticket, walk the catalog:

1. **Identify the trigger category** (lifecycle? signal? texture? UndoRedo?)
2. **For each rule under that trigger, ask: does this rule apply here?**
3. **If yes:** check whether the implied items are addressed
4. **If addressed:** log the check as PASS in audit trail
5. **If not addressed:** raise a blocker OR defer with explicit DEF-NNN tracker entry
6. **Move to the next concept**

This walk is mandatory in Phase 1.G. The Semantic Dependency Engineer is the role doing the walk. Other roles (Inspector Specialist, Resource System Specialist, etc.) provide domain-specific input when consulted.

### When the catalog says "addressed elsewhere"

Some implied items are addressed by other studio protocols:
- "UndoRedo through EditorUndoRedoManager" is owned by UndoRedo Specialist
- "Theme integration" is owned by Theme/UI Specialist
- "Translation wrapping" is owned by Localization Engineer

The Semantic Dependency Engineer cross-references: did the relevant role address this? If yes, log the cross-reference. If no, raise a blocker.

### When the catalog is silent

The catalog has 100+ rules but cannot cover every domain. When a concept doesn't match a catalog rule:

1. The Semantic Dependency Engineer thinks: what are the implied changes anyway?
2. Documents the thinking in the audit trail
3. Proposes a new catalog rule if the same situation is likely to recur
4. Studio Knowledge Curator promotes the proposal to a permanent catalog entry after 3+ occurrences

This is how the catalog grows. It is not static.

---

## Output: the integration report (Phase 1.G)

At Phase 1.G close, the integration report contains the catalog walk results:

```markdown
## Semantic dependency audit

### Concepts introduced/changed this ticket
- C1: new EditorInspectorPlugin
- C2: new Vector3 custom drawer
- C3: new "velocity" exported property
- C4: new "velocity_changed" signal

### Catalog walk

#### C1: new EditorInspectorPlugin
- A1 (add_*/remove_* symmetry): PASS — add at plugin.gd:24, remove at :47
- A2 (_enter_tree/_exit_tree): PASS — _exit_tree mirrors _enter_tree
- C1 (custom drawer): PASS — covered under C2

#### C2: new Vector3 custom drawer
- C1 (custom drawer for property): PASS — drawer commits via UndoRedo (L1)
- L1 (mutating action): PASS — EditorUndoRedoManager used; action name "Set Vector Field"
- L2 (drag-style): PASS — drag merges to single action
- K1 (editor theme): PASS — colors pulled from EditorInterface theme
- K3 (focus mode): PASS — focus_mode = FOCUS_ALL; tab order verified
- M1 (Android editor): N/A — desktop only, per ticket scope

#### C3: new "velocity" exported property
- C2 (@export with hint): PASS — PROPERTY_HINT_RANGE used
- C2 implied (default value): PASS — Vector3.ZERO
- C2 implied (revert): PASS — Vector3.ZERO is the default; standard revert applies
- Q1 (new public API): PASS — README section "Velocity field" added

#### C4: new "velocity_changed" signal
- B2 (signal emit/listen): PASS — emitted from drawer commit; listened by example test
- B1 (connect/disconnect): N/A — signal is emitted, no plugin-internal listener
- Q1 (new public API): PASS — signal documented in README

### Catalog rules considered but not applied
- E* (texture patterns): no textures in this ticket
- F* (shader patterns): no shaders
- T* (multiplayer): N/A

### Deferred items
- DEF-014: Tutorial walkthrough section for VECTOR_FIELD use (deferred to next minor release; tracked)
```

---

## Anti-patterns this catalog prevents

| Anti-pattern | Caught by |
|--------------|-----------|
| Added a connect but no disconnect | A1, B1 |
| Diff texture without normal map at same res | E1, E2 |
| New signal but no listener anywhere | B2 |
| Custom Resource that holds Node reference | D1 |
| Inspector drawer without UndoRedo | C1, L1 |
| Add custom type but no remove on disable | A1, G1 |
| Hardcoded color in plugin UI | K1 |
| New file added but never referenced | S1 |
| Behavior change without CHANGELOG | Q2 |
| User-facing string without tr() | P1 |
| _process with linear scene scan | N3 |
| Plugin writes to user-home path | O2 |

---

End of Semantic Dependency Engine. This protocol is the studio's primary defense against the "domino effect" failure mode. Used together with `impact-analysis-protocol.md` (syntactic layer), it forms a two-layer dependency detection system.
