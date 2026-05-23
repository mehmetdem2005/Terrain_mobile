# Clean Architecture Manifesto

This is the studio's binding doctrine for what professional code looks like. Where `architectural-quality-audit.md` defines the **review process** and `spaghetti-pattern-catalog.md` defines **what to avoid**, this document defines **what to do**. The positive rules. The shape professional code takes.

This is not aspirational; this is the spec. Every L/XL ticket's output is measured against it. The Clean Code Officer and Architectural Quality Auditor use this as their checklist.

The user's core demand, captured exactly:
> "Çalışıyor yetmez. Sonradan büyüyünce dağılmıyorsa iyi koddur."
> ("Working isn't enough. Code is good if it doesn't fall apart when it grows.")

This is the studio's definition of clean code. Everything in this document serves that test.

---

## The five clean architecture invariants

These are the binding rules. Every plugin shipped from the studio must satisfy all five.

### Invariant 1: One system = one responsibility

A "system" in this context = a logical subsystem of the plugin (input handling, persistence, UI, AI, math). Each system has exactly one responsibility. The responsibility can be stated in one sentence.

If you cannot state a system's responsibility in one sentence, OR if the sentence has "and" in it, the system is doing too much.

**Examples:**
- "The PlayerController handles player movement and input." → ✓ one responsibility (movement, which includes its input)
- "The PlayerController handles player movement, input, animation, and audio." → ✗ four responsibilities, four "and"s
- "The SaveManager handles persistence of game state to disk." → ✓ one responsibility
- "The SaveManager handles persistence and UI updates and analytics." → ✗ three responsibilities

**Test:** Each system gets a one-sentence description in the architecture doc (Phase 1.C). If multiple sentences or "and" conjunctions appear, split the system.

### Invariant 2: One file = one clear job

Every file in the plugin has a job statable in one short phrase. The file name should reflect the job.

| File | Job (one phrase) | OK? |
|------|------------------|-----|
| `player_controller.gd` | "controls the player" | ✓ |
| `enemy_spawner.gd` | "spawns enemies" | ✓ |
| `ui_controller.gd` | "manages the UI lifecycle" | ✓ |
| `helpers.gd` | "various helper functions" | ✗ — vague, becomes a dumping ground |
| `main.gd` | "everything that didn't fit elsewhere" | ✗ — anti-pattern |
| `manager.gd` | "manages stuff" | ✗ — meaningless |

**Test:** File name + a one-phrase job description must exist in the architecture doc. Names like `helpers`, `utils`, `main`, `manager`, `manager.gd` (alone, without context) are flagged for review — they tend to become catch-alls.

If a `helpers.gd` is genuinely necessary, the job is "internal utility functions for the math module" — namespaced, scoped. Not "general helpers."

### Invariant 3: One function = one operation

Every function does exactly one thing. The function name describes that thing.

**Bad:**
```gdscript
func do_everything():
    ...

func update():
    refresh_display()
    save_to_disk()
    process_input_queue()
    update_telemetry()
```

**Good:**
```gdscript
func move_player(direction: Vector2, delta: float) -> void:
    velocity = direction.normalized() * speed
    move_and_slide()

func check_ground() -> bool:
    return is_on_floor()

func update_camera(target_position: Vector3) -> void:
    camera.global_position = target_position + camera_offset

func apply_damage(amount: float, source: Node) -> void:
    health -= amount
    damage_taken.emit(amount, source)
```

**Test:** If you read a function's name and then read its body, do they tell the same story? If the body does more than the name promises, split.

**Special note on length:** This invariant doesn't say "short." A 100-line function that does one well-defined operation (e.g., a single mathematical algorithm) is fine. The test is one *operation*, not one *line range*.

### Invariant 4: Systems communicate by signals/events, not by reaching across

Systems must not reach into each other's internals. They communicate through:
- **Signals/events** (preferred default)
- **Public methods on a well-defined interface** (when call-and-response is needed)
- **Resource exchanges** (when data passes between them)

**Forbidden:**
```gdscript
# Player reaches across into other systems
player.enemy.ui.save_manager.weather.something()
ui_manager._internal_state.cached_value = 5
inspector._drawer_pool[0].force_refresh()
```

**Required:**
```gdscript
# Signals declared on player
signal player_died
signal health_changed(new: float, old: float)
signal damage_taken(amount: float, source: Node)

# Other systems connect to what they need
func _ready():
    player.player_died.connect(_on_player_died)
    player.health_changed.connect(_on_health_changed)
```

**Test:** For every cross-system communication, identify whether it's:
- **Signal-driven** (preferred — A emits, B listens, A doesn't know about B)
- **Method call on a defined interface** (acceptable — B has a documented method, A calls it)
- **Reaching through** (forbidden — A accesses B's internals or chains through C to reach D)

The Architectural Quality Auditor maps all cross-system communications. Any "reaching through" pattern is a blocker.

**One exception:** within a single system, internal modules can directly call each other (a system is one cohesive unit). The invariant applies *between* systems.

### Invariant 5: Configuration is not hardcoded

Magic numbers, magic strings, and configuration values are not embedded in code logic. They are either:
- **Exported via `@export`** so the user can adjust in the inspector
- **Constants at the top of the file** with descriptive names
- **In a Resource (`.tres`)** if the configuration is reusable or complex
- **In project settings** if it's a project-wide preference

**Forbidden:**
```gdscript
func _process(delta):
    velocity.x = direction.x * 7.3  # what is 7.3?
    if health < 23:  # why 23?
        play_low_health_sound()
    if get_tree().get_frame() % 60 == 0:  # why 60?
        check_for_save()
```

**Required:**
```gdscript
@export var move_speed := 7.3
@export var low_health_threshold := 23
const SAVE_CHECK_INTERVAL_FRAMES := 60

func _process(delta):
    velocity.x = direction.x * move_speed
    if health < low_health_threshold:
        play_low_health_sound()
    if get_tree().get_frame() % SAVE_CHECK_INTERVAL_FRAMES == 0:
        check_for_save()
```

**Test:** Scan for literal numbers (other than 0, 1, -1) and literal strings used as identifiers. Each one needs a justification: is it a true constant of the universe (PI, sqrt(2)), or is it a tunable/config value that should be exported?

---

## The "doesn't fall apart when it grows" test

This is the user's stated test, made operational. The studio applies it before sign-off:

For every L/XL ticket's deliverable, ask:

1. **If I added one new feature, how many files would I need to touch?**
   - 1-3 files: ✓ healthy
   - 4-6 files: ⚠ acceptable but watch
   - 7+ files: ✗ coupling too high; restructure

2. **If I removed one module, how much else would break?**
   - 1-2 callers, all easy to update: ✓ healthy reversibility
   - Several callers but isolated: ⚠ acceptable
   - "Half the codebase": ✗ god object; restructure

3. **If a new engineer joined and read the README + one entry-point file, would they know where to look for X?**
   - "Look in <directory>/<file>": ✓ discoverable
   - "It's somewhere in here, search for it": ✗ disorganized

4. **If this plugin grew 3× in features over a year, would the structure still hold?**
   - "Add new files to the right subdirectories, edit a couple of entry points": ✓
   - "Need to refactor everything because the structure assumed only a few features": ✗

The Architectural Quality Auditor formally answers these four questions in their Phase 1.G report. Failing answers block sign-off.

---

## The standard plugin folder structure

The studio uses this folder structure as the **default** for any plugin. Tickets can deviate with explicit justification (recorded in the Phase 1.C architecture doc), but the default is the default for a reason — it satisfies the five invariants automatically.

```
addons/<plugin_name>/
├── plugin.cfg                   # Plugin discovery (Godot reads this)
├── README.md                    # User-facing documentation
├── CHANGELOG.md                 # Version history (XL plugins)
├── LICENSE                      # Required for Asset Library
├── icon.png                     # 16x16 plugin icon
│
├── core/                        # Plugin lifecycle and entry points
│   ├── plugin.gd                # EditorPlugin entry (referenced from plugin.cfg)
│   ├── app_state.gd             # Global state if needed (use sparingly)
│   └── plugin_settings.gd       # EditorSettings integration
│
├── api/                         # External API integration (if applicable)
│   ├── api_client.gd
│   ├── api_request.gd
│   └── api_response_parser.gd
│
├── agents/                      # AI agents (if applicable to this plugin)
│   ├── planner_agent.gd
│   ├── executor_agent.gd
│   ├── debugger_agent.gd
│   └── reporter_agent.gd
│
├── pipeline/                    # Task orchestration / workflows
│   ├── task_queue.gd
│   ├── rate_limiter.gd
│   ├── model_router.gd
│   └── operation_router.gd
│
├── ui/                          # User-facing UI (inspector, dock, panels)
│   ├── main_panel.gd
│   ├── chat_panel.gd
│   ├── task_panel.gd
│   ├── settings_panel.gd
│   └── widgets/                 # Reusable UI widgets
│       └── ...
│
├── inspector/                   # EditorInspectorPlugin and drawers
│   ├── inspector_plugin.gd
│   └── drawers/
│       └── <type>_drawer.gd
│
├── validation/                  # Input/data validation
│   ├── json_validator.gd
│   ├── response_validator.gd
│   └── schema_validator.gd
│
├── actions/                     # Discrete operations
│   ├── file_action_executor.gd
│   ├── scene_action_executor.gd
│   └── script_action_executor.gd
│
├── safety/                      # Backup, staging, rollback
│   ├── backup_manager.gd
│   ├── staging_manager.gd
│   └── file_guard.gd
│
├── logging/                     # Logging and tracing
│   ├── error_logger.gd
│   └── execution_trace_logger.gd
│
├── persistence/                 # Save/load, settings storage
│   ├── save_manager.gd
│   └── settings_store.gd
│
├── domain/                      # Pure domain logic (no Godot dependencies if possible)
│   ├── <concept>.gd
│   └── ...
│
├── resources/                   # Plugin-shipped .tres / .res / .png / .svg
│   ├── icons/
│   ├── themes/
│   └── presets/
│
└── translations/                # i18n (if applicable)
    ├── messages.en.translation
    └── messages.tr.translation
```

### Folder usage rules

- **`core/`** — only lifecycle, never business logic
- **`ui/`** — only presentation; no business logic, no persistence calls
- **`domain/`** — pure logic; no Godot-editor dependencies if possible (this is what survives engine updates best)
- **`actions/`** — discrete, named operations (one file per major operation)
- **`safety/`** — anything related to preventing damage (backups, dry-run, rollback)
- **`logging/`** — every log entry goes through here; no direct `print()` in other files

### Subfolder creation rule

If a folder accumulates 7+ files, evaluate: is there a natural sub-grouping? If yes, create a subfolder. If no, leave it (sometimes 10 small files in one folder is fine).

If a folder has only 1 file, evaluate: is the folder pulling its weight? Sometimes yes (signals future growth); sometimes the file should be promoted up.

### Folders that are flagged by default

These folder names are anti-patterns; their use requires justification:
- `helpers/` — too vague; what kind of helpers?
- `utils/` — same
- `misc/` — by definition, accumulates anything
- `lib/` — meaningless without context
- `common/` — sometimes legitimate, but often a dumping ground

If you need a folder for cross-cutting utilities, give it a *named* purpose: `math/`, `string_utils/`, `geometry/`. Specific names resist becoming dumping grounds.

---

## Mapping the user's example to the manifesto

The user provided this folder layout for an AI assistant plugin:

```
addons/ai_assistant/
  core/
    ai_assistant_plugin.gd
    app_state.gd
  api/
    api_client.gd
    api_request.gd
    api_response_parser.gd
  agents/
    planner_agent.gd
    executor_agent.gd
    debugger_agent.gd
    reporter_agent.gd
  pipeline/
    task_queue.gd
    rate_limiter.gd
    model_router.gd
    operation_router.gd
  ui/
    main_panel.gd
    chat_panel.gd
    task_panel.gd
    settings_panel.gd
  validation/
    json_validator.gd
    response_validator.gd
  actions/
    file_action_executor.gd
    scene_action_executor.gd
    script_action_executor.gd
  safety/
    backup_manager.gd
    staging_manager.gd
    file_guard.gd
  logging/
    error_logger.gd
    execution_trace_logger.gd
```

This is the studio's canonical reference example. Every file name passes the "one phrase job" test (Invariant 2). Every folder has a clear responsibility (Invariant 1). Cross-folder communication happens through the pipeline layer using signals/events (Invariant 4). No magic numbers visible in the structure (Invariant 5 implied — would be checked at file level).

When the studio gets an ambiguous design situation, the Plugin Design Lead references this layout as the baseline.

---

## Pre-flight folder check (Phase 1.D)

During Phase 1.D (Planning), the Producer + Tools Lead lay out the folder structure for the plugin. Before any code is written:

1. List every planned file
2. For each, write the one-phrase job
3. Assign to a folder per the standard structure
4. Check: does any folder accumulate 7+ files that don't subdivide naturally?
5. Check: any file name vague enough to become a dumping ground?
6. Check: any folder named with anti-pattern term (helpers, utils, misc)?

If any check fails, restructure before coding begins. Restructuring file layout is cheap before code exists; expensive after.

---

## The five invariants — gate checklist

Used by Clean Code Officer + Architectural Quality Auditor at Phase 1.G. Every invariant must verifiably hold.

### Invariant 1 check
- [ ] Each system has a one-sentence responsibility documented (in architecture doc)
- [ ] No system's responsibility statement contains "and"
- [ ] System count should match how systems split across files (no system fragmented confusingly; no file housing multiple systems)
- [ ] No system is doing more than its stated responsibility (read the code; verify)

### Invariant 2 check
- [ ] Every file has a one-phrase job
- [ ] No file name is in the anti-pattern list (helpers, utils, main, manager.gd alone) without justification
- [ ] No file is doing more than its named job

### Invariant 3 check
- [ ] No function named `update`, `process`, `do_stuff`, `handle_event`, or other vague names without context
- [ ] Each function's body matches its name's promise
- [ ] No function tangles 3+ unrelated concerns (input + business + UI + persistence in one func is a Tangled Function per S-005)

### Invariant 4 check
- [ ] Cross-system communications mapped (in architecture audit)
- [ ] No "reaching through" patterns (`a.b.c.d.method()`)
- [ ] Signals/events used as the default mechanism for cross-system communication
- [ ] Public method calls only across well-defined interfaces, never into module internals
- [ ] No back-references between systems (S-010 from spaghetti catalog)

### Invariant 5 check
- [ ] Scan for magic numbers (literal integers/floats other than 0, 1, -1, π, etc.); each should be a named constant or @export
- [ ] Scan for magic strings used as identifiers (action names, type tags); each should be a constant or enum
- [ ] All configurable values use @export or are loaded from .tres / project settings

### Doesn't-fall-apart test
The studio applies this test qualitatively. The numbers below are **indicators**, not rules — a single feature touching 4 files isn't automatically wrong, but it's a signal to check whether coupling is necessary. Use these as smell-detectors, not gates.

- [ ] Adding a typical new feature touches roughly 3 files or fewer (more = check coupling)
- [ ] Removing a module breaks only easily-updatable callers
- [ ] A new engineer can find feature X in the codebase via README + one entry-point file
- [ ] The structure would scale to several times current feature count without rework

---

## What this manifesto does NOT require

This manifesto is about structural cleanliness. It does not impose:

- Specific design patterns (no mandatory Singleton, Observer, Strategy, etc. — use what fits)
- Specific paradigms (OO vs functional within GDScript — use what fits)
- Specific test framework (the studio doesn't mandate GUT, etc.)
- Specific naming conventions beyond Godot defaults (snake_case for funcs/vars, PascalCase for classes — already in the Coding Standards Enforcer's domain)

The manifesto is structural. Style is handled elsewhere.

---

## How violations are scored

The Architectural Quality Auditor reports per-invariant in their Phase 1.G output:

| Invariant | Status |
|-----------|--------|
| 1: One system = one responsibility | PASS / WEAK / FAIL |
| 2: One file = one clear job | PASS / WEAK / FAIL |
| 3: One function = one operation | PASS / WEAK / FAIL |
| 4: Systems communicate by signals/events | PASS / WEAK / FAIL |
| 5: Configuration is not hardcoded | PASS / WEAK / FAIL |
| Doesn't-fall-apart test | PASS / WEAK / FAIL |

Verdict:
- All PASS → ticket can advance
- 1-2 WEAK, none FAIL → PASS_WITH_CONDITIONS (conditions logged)
- 3+ WEAK, or any FAIL → ticket returns to refactor

---

## When the user requests something that violates the manifesto

Sometimes a user asks for "a quick script that does X" where X is genuinely a single thing and the manifesto would be overkill. The studio's response:

1. Tech Director triages: this is an S or M ticket; the manifesto applies in a relaxed form
2. The relaxed form: invariants 1-5 still apply *to the scale of the work*; the folder template is not required for a 100-line script
3. A 100-line script with magic numbers everywhere is still a fail (Invariant 5 doesn't get a free pass for being short)

Conversely, if the user asks for "a small plugin" but the scope is actually 1000+ lines: the studio's response is to apply the full manifesto. Scope determines treatment.

---

## Why this is the studio's hill

The user said: "Çalışıyor yetmez. Sonradan büyüyünce dağılmıyorsa iyi koddur." This sentence is the studio's mission statement for code quality.

A studio that ships "working" code that becomes spaghetti at scale is producing technical debt. A studio that ships code structured to grow gracefully is producing real engineering work. This manifesto encodes the difference.

Every reviewer at the studio asks themselves the same question on every ticket: **would this codebase still be sane after a year of additions?** If yes, ship. If no, refactor before ship.

That is the standard. That is what the studio's name on a plugin is supposed to mean.
