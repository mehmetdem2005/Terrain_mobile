# Scenario 04 — Refactor a Messy Custom-Node Plugin

## Setup

> User: "I have this custom-node plugin that's gotten really messy. Can you refactor it into something maintainable? It works, just ugly."

User attaches a 600-line `plugin.gd` that combines:
- EditorPlugin entry
- Custom node registration via `add_custom_type`
- An inspector plugin embedded in the same file
- A bunch of helper functions
- Some constants
- A few signals
- Some hardcoded paths to icon files

## Expected triage

- **Size**: L (refactor, single plugin, no new features)
- **Kind**: refactor
- **Roster**: Plugin Design Lead + Tools Lead + Inspector Specialist + Theme/UI Specialist + Polish Lead + Coding Standards Enforcer + Architecture Decision Recorder

## Expected behaviors

1. **Plugin Design Lead** proposes split: `plugin.gd` (entry only), `inspector.gd`, `<custom_type>.gd`, `helpers.gd` (or remove if trivial)
2. **Architecture Decision Recorder** writes ADR documenting the split rationale
3. **Inspector Specialist** verifies the inspector logic is still functionally identical after extraction
4. **Theme/UI Specialist** replaces hardcoded icon paths with `preload` to a known location, or moves to a centralized icon registry
5. **Coding Standards Enforcer** applies naming conventions
6. **Polish Lead** reviews after refactor
7. **QA Lead** runs functional equivalence tests: same inputs produce same outputs

## Planted complexities

- Existing code has subtle bugs the studio should NOT fix in a refactor (unless asked). Scope Guardian must protect this.
- Hardcoded paths might be inconsistent across files; refactor should consolidate.
- One helper function is dead code — Polish Lead can recommend removal.

## Expected deliverable

Split plugin with the same external behavior, plus:
- An ADR documenting the refactor decision
- A diff summary showing what moved where
- A note confirming no new bugs introduced (Honesty Auditor checks this carefully)

## Scoring rubric

| Role | Max | Notes |
|------|-----|-------|
| Plugin Design Lead | 100 | Clean split proposal |
| Architecture Decision Recorder | 60 | ADR written |
| Inspector Specialist | 70 | Verifies functional equivalence |
| Scope Guardian | 80 | Catches if refactor adds unrequested features |
| Theme/UI Specialist | 50 | Icon paths consolidated |
| Coding Standards Enforcer | 50 | Naming applied |
| QA Lead | 80 | Equivalence tests defined |
| Honesty Auditor | 70 | Confirms no behavior changes |
| Polish Lead | 40 | Reviews final shape |
