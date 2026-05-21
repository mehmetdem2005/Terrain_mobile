# Scenario 05 — Custom File Importer

## Setup

> User: "I need an EditorImportPlugin that imports `.csv` files as a custom `TableResource` that I can query via cell coordinates. Should support import presets for: 'with header row' and 'no header row'. CSV has variable number of columns per row."

## Expected triage

- **Size**: XL (custom file format, full importer, resource type design, multi-file plugin, public API surface)
- **Mobile flag**: false (not mentioned)
- **Roster**: full XL roster including pre-production phase

## Expected behaviors

1. **Pre-production**: Feasibility Analyst confirms EditorImportPlugin can produce custom resources; Plugin Design Lead writes design doc
2. **Custom resource design**: `TableResource` extends Resource; has `cells` storage, `header` if applicable, query method
3. **Importer implementation**: implements all required `EditorImportPlugin` methods
4. **Preset implementation**: 2 presets with correct preset_count = 2
5. **CSV parsing**: handles edge cases — quoted strings, commas in quoted strings, empty cells, trailing newline, BOM
6. **Variable column count**: each row's cell array length may differ
7. **Performance**: streaming parse for large files (don't load all into memory if >10MB)
8. **API stability**: TableResource.query(x, y) is public API; signature should be documented and stable
9. **Migration**: if a future version changes TableResource format, migration path

## Planted complexities

| Trap | What should happen |
|------|--------------------|
| CSV with quoted commas: `"a, b", c` | Edge Case Hunter catches; parser handles |
| CSV with embedded newlines in quoted cells | Edge Case Hunter catches |
| UTF-8 BOM at file start | Edge Case Hunter catches |
| Very large file (100MB) | Performance Engineer suggests streaming |
| Header row containing duplicate column names | Edge Case Hunter notes; design decision (rename / error / accept) |
| User-provided CSV path with `..` traversal | Security Reviewer catches |

## Expected deliverable

`addons/csv_table_importer/`:
- `plugin.cfg`
- `plugin.gd`
- `csv_importer.gd` — EditorImportPlugin subclass
- `table_resource.gd` — Resource subclass with `class_name TableResource`
- `csv_parser.gd` — internal parser with edge case handling
- `README.md` with usage example
- `TUTORIAL.md` — cookbook walkthrough
- `LICENSE`
- Total LOC: ~600-900

## Scoring rubric

| Role | Max | Notes |
|------|-----|-------|
| Plugin Design Lead | 100 | Design doc exists |
| Importer Specialist | 100 | All EditorImportPlugin methods correct |
| Resource System Specialist | 80 | TableResource design clean |
| Edge Case Hunter | 100 | Catches CSV edge cases |
| Security Reviewer | 80 | Path traversal protection |
| Performance Engineer | 70 | Large file consideration |
| API Stability Officer | 60 | Public API documented |
| Data Migration Engineer | 40 | Migration plan written |
| Technical Writer | 60 | README clear |
| Tutorial Writer | 50 | Cookbook walkthrough exists |
| Architecture Review Board | 80 | All 3 seats engaged |
| Studio Head | 60 | Sign-off |
