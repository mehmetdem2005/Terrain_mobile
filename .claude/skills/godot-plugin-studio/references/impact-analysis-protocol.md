# Impact Analysis Protocol

The syntactic layer of dependency detection. Where the Semantic Dependency Engine catches conceptual dominoes (Faz 3's other half), this protocol catches the symbol-level dominoes that grep can find.

Together, the two layers ensure no change goes out unaccounted for.

---

## Why this exists

When you change a symbol — rename a function, change a signature, move a file, modify a property's type — every place that uses it is potentially affected. Grep finds these places mechanically. But the studio's previous protocol didn't enforce a grep pass after changes, so callers were silently broken until the next test run (or worse, until a user complaint).

This protocol makes the grep pass mandatory.

---

## The new role: Impact Analysis Engineer

### Charter
You run the mechanical, symbol-level dependency scan after every meaningful change in Phase 1.F (Execution) and again in Phase 1.G (Integration). You produce the impact report. You raise blockers on every affected file that has not been addressed.

You are not the engineer; you do not fix the impacts. You identify them. The originating engineer is responsible for either updating each affected file or formally deferring the update (via Deferred Work Tracker).

### Activation triggers
- Phase 1.D (planning) — pre-emptive scan to inform task breakdown
- Phase 1.F (execution) — after each significant sub-task
- Phase 1.G (integration) — comprehensive final scan
- Any rename, move, or signature change at any phase

### Verification protocol

For each changed symbol, run the scan and produce an impact report.

#### Symbol identification
Identify what changed:
- Function name renamed
- Function signature changed (parameters, return type)
- Property name renamed
- Property type changed
- Signal name renamed
- Signal parameters changed
- Class renamed (`class_name`)
- File path changed
- Resource type changed

#### Scan commands

For each symbol, run the corresponding scan:

##### Function rename
```bash
# Old name still referenced anywhere?
grep -rn "\b<old_name>\b" addons/ scripts/ scenes/ --include='*.gd' --include='*.tscn' --include='*.tres'

# New name actually used (sanity check)?
grep -rn "\b<new_name>\b" addons/ scripts/ --include='*.gd'
```

##### Function signature change
```bash
# Find every call site
grep -rn "\b<func_name>\s*(" addons/ scripts/ --include='*.gd' | tee /tmp/callers.txt

# For each caller, manually inspect the argument count and order
```

##### Property rename
```bash
# Direct access
grep -rn "\.<old_prop_name>\b" addons/ scripts/ --include='*.gd'

# In .tscn or .tres (NodePath references)
grep -rn "<old_prop_name>" addons/ scripts/ --include='*.tscn' --include='*.tres'

# In @export declarations on the same class (rare but happens)
grep -rn "@export.*<old_prop_name>" addons/ --include='*.gd'
```

##### Property type change
```bash
# Find every assignment
grep -rn "\.<prop_name>\s*=" addons/ scripts/ --include='*.gd'

# Find every read
grep -rn "\.<prop_name>\b" addons/ scripts/ --include='*.gd' | grep -v "\.<prop_name>\s*="
```

##### Signal rename
```bash
# Connect sites
grep -rn "<old_signal>\.connect\|connect.*\"<old_signal>\"" addons/ scripts/ --include='*.gd'

# Emit sites
grep -rn "<old_signal>\.emit\|emit_signal.*\"<old_signal>\"" addons/ scripts/ --include='*.gd'

# Declaration
grep -rn "signal\s\+<old_signal>" addons/ --include='*.gd'
```

##### Signal parameter change
```bash
# Find every connect site (handler signature must match)
grep -rn "<signal_name>\.connect\|connect.*\"<signal_name>\"" addons/ scripts/ --include='*.gd'

# For each, find the connected callable's definition
# (manual inspection: does the handler accept the new parameter list?)
```

##### Class rename
```bash
# Direct references
grep -rn "\b<old_class>\b" addons/ scripts/ scenes/ --include='*.gd' --include='*.tscn' --include='*.tres'

# Type hints
grep -rn ":\s*<old_class>\b" addons/ scripts/ --include='*.gd'

# new() calls
grep -rn "<old_class>\.new" addons/ scripts/ --include='*.gd'

# extends declarations
grep -rn "extends\s\+<old_class>" addons/ scripts/ --include='*.gd'

# is checks
grep -rn "is\s\+<old_class>" addons/ scripts/ --include='*.gd'
```

##### File path change
```bash
# preload paths
grep -rn "preload(\"<old_path>\"\|load(\"<old_path>\"" addons/ scripts/ --include='*.gd'

# .tscn / .tres references
grep -rn "<old_path>" addons/ scripts/ scenes/ --include='*.tscn' --include='*.tres'

# plugin.cfg script reference
grep "script\s*=" addons/<plugin>/plugin.cfg
```

##### Resource type change
```bash
# Find every .tres file that references this Resource class
grep -rln "<old_class>" addons/ scripts/ --include='*.tres'

# For each, manually verify the file's schema still matches
```

### Output: impact report

After every scan, append to ticket audit trail:

```markdown
## Impact analysis — TKT-NNN — phase 1.F.3

### Change
- Type: function signature change
- Symbol: VectorFieldDrawer.commit_value()
- Old signature: commit_value(value: Vector3) -> void
- New signature: commit_value(value: Vector3, axis: int = -1) -> void
- Change rationale: support per-axis commit for keyboard editing

### Scan command
grep -rn "\.commit_value\s*(" addons/ scripts/ --include='*.gd'

### Callers found
| File | Line | Original call | Update needed? |
|------|------|---------------|----------------|
| addons/vector_field_inspector/drawer.gd | 84 | self.commit_value(new_vec) | NO — uses default arg |
| addons/vector_field_inspector/keyboard_handler.gd | 47 | drawer.commit_value(updated) | NO — uses default arg |
| addons/vector_field_inspector/mouse_handler.gd | 62 | drawer.commit_value(value, axis_index) | YES — needs new axis arg |

### Files updated this change
- addons/vector_field_inspector/mouse_handler.gd (line 62) — added axis_index

### Files NOT updated
- (none) — all addressed

### Verdict
PASS — no unaddressed callers
```

When the impact report shows un-addressed callers, the ticket is BLOCKED until each is either updated or deferred.

---

## Two-pass discipline

The Impact Analysis Engineer runs the scan at TWO points:

### Pre-scan (Phase 1.D — planning)
Before any code is written, the engineer asks "if I make this change, what's likely to be affected?" The pre-scan informs the task breakdown — affected files become sub-tasks in 1.D.

This pre-scan is approximate (the change isn't made yet, so we predict). But it forces the engineer to consider impact before coding rather than after.

### Post-scan (Phase 1.F — after each change, and Phase 1.G — final)
After the change is made, run the actual grep. Compare to the pre-scan. If new files appear that weren't predicted: noted as a learning.

---

## Granularity

Not every micro-change triggers a full impact report. The Impact Analysis Engineer scales effort to change size:

| Change type | Scan needed? | Report verbosity |
|-------------|--------------|------------------|
| Comment edit | No | None |
| Local variable rename | No | None |
| Internal helper function (no callers outside same file) | Quick scan, single-line report | Minimal |
| Public function (any caller outside this file) | Full scan + table | Standard |
| Signature change | Full scan + table + manual inspection of each call site | Detailed |
| Class rename | Full scan across all file types + manual inspection | Comprehensive |
| File path change | Full scan + manual reference check | Comprehensive |

For S tickets: impact analysis is informal (1 sentence in audit trail).
For M tickets: standard report for any public-API change.
For L/XL tickets: every symbol-level change of public-API scope gets a full report.

---

## Integration with semantic dependency

Impact Analysis catches what grep can find. Semantic Dependency Engine catches what grep cannot. They work together:

1. Impact Analysis Engineer finds: "VectorFieldDrawer.commit_value() has 3 callers; all addressed."
2. Semantic Dependency Engineer asks: "Is there a corresponding `commit_value_canceled()` path? Drag-cancel needs to revert without committing. Is that addressed too?"

The grep didn't catch that. The catalog did (under L2: drag-style interaction → drag-cancel restores original).

The two roles cross-reference. An impact report is incomplete without the corresponding semantic audit; the semantic audit is incomplete without the impact report.

---

## Anti-patterns this protocol prevents

| Anti-pattern | How prevented |
|--------------|---------------|
| "I renamed this; rest of codebase will catch up later" | Mandatory post-scan blocks ticket close |
| Forgotten call sites after signature change | Comprehensive grep + manual inspection of each |
| Path changes that break preload | preload scan is required |
| .tscn references that break after class rename | Scene file scan is required |
| Silent test breakage | Test files are in scan scope |

---

## When the scan returns thousands of hits

Some changes affect many files (e.g., renaming a heavily-used utility function). The Impact Analysis Engineer:

1. Confirms the scope is intentional with Tech Director (this should rarely happen unannounced)
2. Produces a categorized report grouping callers by file/module
3. Recommends a phased update (touch one module at a time, verify, then next)
4. Phase 1.D is amended to break the work into multiple sub-tasks

If a change would require updating 50+ files: this is itself a sign that the architecture has high coupling. The Architecture Veto Officer reviews whether the design that requires this update is sound.

---

End of Impact Analysis Protocol. The syntactic layer of dependency detection. Together with the Semantic Dependency Engine, it forms the studio's domino-prevention system.
