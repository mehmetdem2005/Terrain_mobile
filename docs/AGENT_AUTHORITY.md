# Ajan Yetki Matrisi — MobileTerrain3D

> agent-governance skill'i tarafından üretilir/yenilenir. Elle düzenleme;
> kaynak: .claude/agents/ tanımları (üretici: scripts/gen_agents.py).
> Standart: docs/STANDARDS.md 4.1 (ISO 42001 AI envanteri), 4.2 (risk sınıfı).
>
> Son denetim: 2026-06-10 — 5/5 kontrol temiz (yetki şişmesi yok, orkestratör
> yazma yetkisiz, sahipsiz worker 0, model israfı yok, çakışma matrisi tanımlı).

## Risk sınıfları

| Sınıf | Tanım | Adet |
|---|---|---|
| R4 tepe orkestrasyon (kod yazamaz) | terrain-orchestrator | 1 |
| R3 delegasyon + yazma | managers | 7 |
| R2 kod yazan worker | fix/ | 50 |
| R1 salt-okur worker | audit/ | 50 |

## Tam envanter (dosya | araçlar | model)

| Ajan | Araçlar | Model |
|---|---|---|
| terrain-orchestrator.md | Agent, Read, Bash, Grep, Glob | opus |
| managers/brush-system-manager.md | Agent, Read, Bash, Grep, Glob, Edit, Write | sonnet |
| managers/chunk-system-manager.md | Agent, Read, Bash, Grep, Glob, Edit, Write | sonnet |
| managers/editor-ui-manager.md | Agent, Read, Bash, Grep, Glob, Edit, Write | sonnet |
| managers/paint-system-manager.md | Agent, Read, Bash, Grep, Glob, Edit, Write | sonnet |
| managers/quality-manager.md | Agent, Read, Bash, Grep, Glob, Edit, Write | sonnet |
| managers/save-system-manager.md | Agent, Read, Bash, Grep, Glob, Edit, Write | sonnet |
| managers/shader-system-manager.md | Agent, Read, Bash, Grep, Glob, Edit, Write | sonnet |
| audit/audit-brush-erode-bounds.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-brush-flatten-cached-read.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-brush-footprint-duplication.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-brush-mask-decompress-leak.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-brush-mask-fallback.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-brush-noise-determinism.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-brush-smooth-dirty-order.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-brush-terrace-clamp.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-chunk-budget.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-chunk-dirty-propagation.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-chunk-map-size-mid-rebuild.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-chunk-multimesh-gc.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-chunk-resize-during-stroke.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-chunk-sync-rebuild-limit.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-chunk-tangent-fill.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-editor-asset-manager-rebuild.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-editor-brush-toggle-on-cursor.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-editor-dropdown-id-mapping.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-editor-input-stroke-order.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-editor-signal-double-connect.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-editor-undo-redo-foliage.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-foliage-multimesh-resize.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-foliage-signal-emission.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-foliage-spacing.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-foliage-transform-from-normal.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-general-deferred-stale-capture.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-general-image-lock-leftovers.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-general-large-range-budget.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-general-stringname-subscript.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-paint-init-mid-stroke.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-paint-null-update.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-paint-shared-ref.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-paint-slot-bounds.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-paint-slot5-silent-fail.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-paint-tool-switch-cache.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-raymarch-binary-search-oob.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-raymarch-edge-camera-below.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-raymarch-iter-cap.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-save-multi-terrain.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-save-packedscene-feasibility.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-save-perform-resave-reachability.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-save-resourcesaver-error-codes.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-save-restore-null-guard.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-save-suppress-flag-leak.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-save-suppress-next-save-hook.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-save-validate-property-effect.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-shader-blank-fallback-cache.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-shader-extraction-syntax.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-shader-pbr-array-padding.md | Read, Grep, Glob, Bash | sonnet |
| audit/audit-shader-uniform-binding.md | Read, Grep, Glob, Bash | sonnet |
| fix/fix-bug-brush-mask-decompress-leak.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-bug-erode-bounds.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-bug-erode-resize-during-stroke.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-bug-flatten-cached-read.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-bug-input-stroke-order.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-bug-paint-null-update-guard.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-bug-paint-shared-ref-duplicate.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-bug-paint-slot-bounds.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-bug-paint-tool-switch-cache-clear.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-bug-shader-blank-cache-invalidate.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-bug-smooth-dirty-order.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-bug-stringname-subscript-audit.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-extract-brush-system.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-extract-chunk-system.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-extract-editor-ui-modules.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-extract-foliage-system.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-extract-heightmap-system.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-extract-input-router.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-extract-persistence-system.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-extract-raymarch-system.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-extract-sculpt-ops.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-extract-shader-system.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-extract-splatmap-system.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-extract-terrain-shader-to-gdshader.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-polish-changes-md.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-polish-debug-print-purge.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-polish-error-message-catalog.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-polish-plugin-version.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-qa-headless-godot-install.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-qa-parse-check-script.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-qa-test-brush-system.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-qa-test-heightmap-system.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-qa-test-multi-terrain-save.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-qa-test-save-roundtrip.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-qa-test-sculpt-ops.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-qa-unit-test-framework.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-save-error-catalog.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-save-multi-terrain-isolation.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-save-plan-b-perform-resave.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-save-restore-defensive-guards.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-save-strip-debug-prints.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-save-suppress-flag-error-path.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-save-tests.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-save-validate-property-cleanup.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-wire-constants.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-wire-diagnostics.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-wire-node-facade.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-wire-plugin-shell.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-wire-save-orchestrator.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
| fix/fix-wire-undo-recorder.md | Read, Edit, Write, Bash, Grep, Glob | sonnet |
