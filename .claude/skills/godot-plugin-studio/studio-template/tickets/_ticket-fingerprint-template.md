# Ticket Fingerprint — TKT-<NNN>

Produced at Phase 1.C close per `references/predictive-prevention-protocol.md` Step 1.

Owner: **Defect Pattern Specialist**

Process: answer every axis yes/no/unsure based on the architecture document from Phase 1.C and the original ticket intent. At the end, summarize which catalog categories apply.

Without this file, Gate L50 fails and Phase 1.D cannot begin.

Delete this header section after filling.

---

## Persistence & I/O
- Touches save data: <yes | no | unsure — and brief note>
- Touches user files (read/write outside user://): <yes | no>
- Touches project files (res:// writes): <yes | no>
- Touches network (HTTP, sockets, multiplayer): <yes | no>

## Editor vs runtime
- Editor-time only (plugin work): <yes | no>
- Runtime-only (game work): <yes | no>
- Both: <yes | no>
- @tool annotations involved: <yes | no>

## Lifecycle surface
- Adds new autoloads: <yes | no>
- Modifies _enter_tree / _exit_tree / _ready / _process / _physics_process: <yes | no — which ones>
- Adds new signals: <yes | no — how many approx>
- Modifies plugin.cfg or project.godot: <yes | no>

## State management
- New persistent state (saved across sessions): <yes | no>
- New session state (lost on quit): <yes | no>
- New state machine: <yes | no>
- Cross-system state references: <yes | no>

## Concurrency & timing
- await / coroutines: <yes | no>
- call_deferred: <yes | no>
- Frame-rate-dependent logic: <yes | no>
- Tweens: <yes | no>
- Timers: <yes | no>

## Rendering & assets
- Custom shaders or materials: <yes | no>
- Procedural geometry: <yes | no>
- Texture loading at runtime: <yes | no>
- Resource sharing across instances: <yes | no>

## Input & UI
- New input actions: <yes | no>
- Touch input required: <yes | no>
- Modal UI (consumes input vs lets through): <yes | no>
- Theme changes: <yes | no>

## Platform & target
- Mobile target: <yes | no>
- Multi-platform target: <yes | no>
- Console target (if applicable): <yes | no>
- Specific Godot version requirements: <yes | no — which>

## Multiplayer (game tickets only)
- RPC calls: <yes | no | N/A>
- MultiplayerSynchronizer: <yes | no | N/A>
- Server-authoritative vs client-authoritative: <which | N/A>

---

## Summary of relevant defect categories

Based on the fingerprint above, the following catalog categories apply to this ticket:

- **Plugin catalog**: <list categories, e.g., "A (Lifecycle), D (Signals), G (Persistence)" — or "not applicable" if game-only>
- **Game catalog**: <list categories, e.g., "GA (Gameplay), GD (Save/Load)" — or "not applicable" if plugin-only>

Total estimated patterns to walk in the predictive checklist: <approximate count>
