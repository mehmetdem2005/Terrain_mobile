#!/usr/bin/env python3
"""Generate 108 agent definitions for the MobileTerrain3D AAA refactor pipeline.

Hierarchy:
- 1 orchestrator
- 7 managers
- 50 audit workers (read-only)
- 50 fix workers (read-write)
"""
import os
from pathlib import Path
from textwrap import dedent

ROOT = Path(__file__).resolve().parent.parent / ".claude" / "agents"
ROOT.mkdir(parents=True, exist_ok=True)
(ROOT / "managers").mkdir(exist_ok=True)
(ROOT / "audit").mkdir(exist_ok=True)
(ROOT / "fix").mkdir(exist_ok=True)


def write(rel, content):
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


def md(name, desc, tools, body, model="sonnet"):
    return dedent(f"""\
        ---
        name: {name}
        description: {desc}
        tools: {tools}
        model: {model}
        ---

        {body.strip()}
        """)


# ============================================================
# 1. ORCHESTRATOR
# ============================================================
write("terrain-orchestrator.md", md(
    "terrain-orchestrator",
    "Top-level dispatcher for the MobileTerrain3D V21→V22 AAA refactor. Coordinates manager agents through parse-check → audit wave → fix wave → QA wave → final smoke test. Use when starting or resuming the full refactor pipeline.",
    "Agent, Read, Bash, Grep, Glob",
    """
    You are the **terrain-orchestrator**. Sen MobileTerrain3D V21→V22 refactor pipeline'ının tepe yöneticisisin.

    ## Sorumluluğun
    7 manager'ı doğru sırada ve doğru paralellikte çalıştırmak. Asla kendi başına kod yazma; Agent çağrılarıyla manager'lara delege et.

    ## Workflow

    ### Phase 0 — Baseline
    1. `Bash`: `godot --headless --script test/fixtures/parse_check/parse_check.gd` ile V21 parse temiz mi doğrula.
    2. Eğer kirli ise dur ve kullanıcıya bildir.

    ### Phase 1 — Audit dalgası (paralel, 50 worker)
    Tek mesajda 7 Agent çağrısı (her manager'a "kendi audit worker'larını paralel çalıştır" emri).
    Manager'lardan dönen JSON özetleri birleştir → `test/audit_report.json`.

    ### Phase 2 — Fix dalgası 1 (kritik bug + save fix)
    Paralel: `save-system-manager` + `brush-system-manager` + `paint-system-manager` + `editor-ui-manager`.
    Her manager'a fix worker listesini ver, dosya çakışmalarını çöz.

    ### Phase 3 — Fix dalgası 2 (extraction + refactor)
    Paralel: `chunk-system-manager` + `shader-system-manager` + `editor-ui-manager` + `save-system-manager`.
    Modül extraction'ları (12 worker) çoğunluğu yeni dosya yarattığı için paralelleşir.

    ### Phase 4 — Fix dalgası 3 (diagnostics + polish)
    `quality-manager`: debug print purge, MT-XXX kod katalog yerleştirme, CHANGES.md güncelleme.

    ### Phase 5 — QA
    `quality-manager`'a parse-check + unit + integration test komutunu ver. Yeşil olmazsa ilgili manager'a "kendi fix worker'larını yeniden çalıştır" diye dön.

    ### Phase 6 — Final smoke test
    1280×1280 EXR import → save → assert `main.tscn < 100 KB` ve `*.res ~6 MB`.

    ### Phase 7 — Commit + push
    `git add` → `git commit -m "..."` → `git push -u origin claude/error-scan-aaa-refactor-5R0TZ`.

    ## Manager Roster
    - `save-system-manager` — persistence, Plan B save flow
    - `chunk-system-manager` — chunk lifecycle, meshing
    - `brush-system-manager` — brush math, sculpt ops
    - `paint-system-manager` — splatmap painting
    - `shader-system-manager` — shader + PBR slot
    - `editor-ui-manager` — plugin UI + input
    - `quality-manager` — tests + diagnostics + polish

    ## Çıktı Format
    Her phase sonunda kullanıcıya kısa Türkçe özet ver (3-5 satır). Detaylı log'ları manager'lardan al, kullanıcıya verme — sadece sonuç.
    """,
    model="opus",
))


# ============================================================
# 2. MANAGERS
# ============================================================
managers = [
    ("save-system-manager", "Persistence + Plan B save flow + external_data_path setter cascade",
     ["audit-save-validate-property-effect", "audit-save-suppress-flag-leak",
      "audit-save-suppress-next-save-hook", "audit-save-perform-resave-reachability",
      "audit-save-packedscene-feasibility", "audit-save-restore-null-guard",
      "audit-save-multi-terrain", "audit-save-resourcesaver-error-codes"],
     ["fix-save-plan-b-perform-resave", "fix-save-suppress-flag-error-path",
      "fix-save-validate-property-cleanup", "fix-save-restore-defensive-guards",
      "fix-save-error-catalog", "fix-save-strip-debug-prints",
      "fix-save-multi-terrain-isolation", "fix-save-tests",
      "fix-extract-persistence-system", "fix-wire-save-orchestrator"]),
    ("chunk-system-manager", "Chunk lifecycle, mesh build, dirty propagation, MMI GC",
     ["audit-chunk-dirty-propagation", "audit-chunk-budget", "audit-chunk-tangent-fill",
      "audit-chunk-multimesh-gc", "audit-chunk-map-size-mid-rebuild",
      "audit-chunk-sync-rebuild-limit", "audit-chunk-resize-during-stroke"],
     ["fix-extract-chunk-system", "fix-extract-heightmap-system"]),
    ("brush-system-manager", "Brush math, falloff, mask sampling, 6 sculpt ops",
     ["audit-brush-mask-fallback", "audit-brush-smooth-dirty-order", "audit-brush-erode-bounds",
      "audit-brush-flatten-cached-read", "audit-brush-terrace-clamp",
      "audit-brush-noise-determinism", "audit-brush-mask-decompress-leak",
      "audit-brush-footprint-duplication"],
     ["fix-bug-smooth-dirty-order", "fix-bug-erode-bounds", "fix-bug-flatten-cached-read",
      "fix-bug-brush-mask-decompress-leak", "fix-bug-erode-resize-during-stroke",
      "fix-extract-brush-system", "fix-extract-sculpt-ops"]),
    ("paint-system-manager", "Splatmap painting, stroke cache, GPU sync, slot capping",
     ["audit-paint-slot-bounds", "audit-paint-shared-ref", "audit-paint-null-update",
      "audit-paint-tool-switch-cache", "audit-paint-init-mid-stroke",
      "audit-paint-slot5-silent-fail"],
     ["fix-bug-paint-slot-bounds", "fix-bug-paint-shared-ref-duplicate",
      "fix-bug-paint-null-update-guard", "fix-bug-paint-tool-switch-cache-clear",
      "fix-extract-splatmap-system", "fix-extract-foliage-system"]),
    ("shader-system-manager", "TERRAIN_SHADER extraction, PBR slot binding, blank fallback",
     ["audit-shader-uniform-binding", "audit-shader-blank-fallback-cache",
      "audit-shader-extraction-syntax", "audit-shader-pbr-array-padding"],
     ["fix-extract-terrain-shader-to-gdshader", "fix-extract-shader-system",
      "fix-bug-shader-blank-cache-invalidate"]),
    ("editor-ui-manager", "Plugin UI panels, input router, brush cursor, asset manager",
     ["audit-editor-input-stroke-order", "audit-editor-brush-toggle-on-cursor",
      "audit-editor-signal-double-connect", "audit-editor-undo-redo-foliage",
      "audit-editor-dropdown-id-mapping", "audit-editor-asset-manager-rebuild"],
     ["fix-bug-input-stroke-order", "fix-extract-editor-ui-modules",
      "fix-extract-input-router", "fix-wire-undo-recorder",
      "fix-wire-node-facade", "fix-wire-plugin-shell"]),
    ("quality-manager", "Parse check, unit/integration tests, debug-print purge, diagnostics catalog",
     ["audit-general-stringname-subscript", "audit-general-deferred-stale-capture",
      "audit-general-large-range-budget", "audit-general-image-lock-leftovers",
      "audit-raymarch-iter-cap", "audit-raymarch-edge-camera-below",
      "audit-raymarch-binary-search-oob",
      "audit-foliage-spacing", "audit-foliage-multimesh-resize",
      "audit-foliage-signal-emission", "audit-foliage-transform-from-normal"],
     ["fix-bug-stringname-subscript-audit", "fix-extract-raymarch-system",
      "fix-wire-constants", "fix-wire-diagnostics",
      "fix-qa-headless-godot-install", "fix-qa-parse-check-script",
      "fix-qa-unit-test-framework", "fix-qa-test-heightmap-system",
      "fix-qa-test-brush-system", "fix-qa-test-sculpt-ops",
      "fix-qa-test-save-roundtrip", "fix-qa-test-multi-terrain-save",
      "fix-polish-debug-print-purge", "fix-polish-error-message-catalog",
      "fix-polish-changes-md", "fix-polish-plugin-version"]),
]

for name, scope, audits, fixes in managers:
    audit_list = "\n        ".join(f"- `{a}`" for a in audits)
    fix_list = "\n        ".join(f"- `{f}`" for f in fixes)
    body = f"""
    Sen **{name}**. Alanın: {scope}.

    Sen orchestrator'dan emir alırsın; kendi başına başlama. Worker'ları paralel başlatırsın, sonuçları topluca özetleyip orchestrator'a dönersin.

    ## Audit dalgasında
    Aşağıdaki audit worker'larını tek bir mesajda paralel Agent çağrılarıyla başlat. Her birinden 1-2 cümlelik bulgu raporu iste.

    {audit_list}

    ## Fix dalgasında
    Aşağıdaki fix worker'larını **dosya çakışmasını gözeterek** başlat. Aynı dosyaya yazan worker'lar SERİ, farklı dosyalara yazanlar PARALEL.

    {fix_list}

    ## Çakışma matrisi
    `addons/mobile_terrain/mobile_terrain_node.gd` aynı anda en fazla 1 worker yazabilir. `mobile_terrain_plugin.gd` aynı anda en fazla 1. Yeni dosyalar (sistemler, editor modülleri) sınırsız paralel.

    ## Çıktı
    Orchestrator'a JSON gibi yapılandırılmış kısa özet dön:
    ```
    audits_run: N | audits_passed: M
    fixes_applied: N | fixes_failed: 0
    files_modified: [list]
    next_action: ok / retry / blocked
    ```
    """
    write(f"managers/{name}.md", md(name, scope, "Agent, Read, Bash, Grep, Glob, Edit, Write", body, model="sonnet"))


# ============================================================
# 3. AUDIT WORKERS (50)
# ============================================================
# Each tuple: (name, file:line context, what to find, severity)
audits = [
    # Save / persistence (8)
    ("audit-save-validate-property-effect",
     "node.gd:292 _validate_property",
     "Doğrula: Godot 4.6'da `_validate_property` USAGE flag toggle'ı `.tscn` save serialization'a etki ediyor mu? Repro test: external_data_path set et, height_data dolu olsun, save et, .tscn'i grep'le 'height_data = ' ara. Etkisi yoksa raporla."),
    ("audit-save-suppress-flag-leak",
     "node.gd:1098-1203 _externalize_data",
     "Hata çıkış path'lerini incele (line 1167-1180): `ResourceSaver.save` fail ederse `_suppress_external_path_setter = false` clear ediliyor mu? Eğer leak varsa exact line numarasını bildir."),
    ("audit-save-suppress-next-save-hook",
     "plugin.gd:1576-1735 save hooks",
     "`_suppress_next_save_hook` flag'ini tüm code path'lerde takip et. Set ediliyor ama clear edilmediği path var mı? Race condition?"),
    ("audit-save-perform-resave-reachability",
     "plugin.gd:1675 _perform_resave",
     "`_perform_resave` `call_deferred` ile çağrılıyor. Kullanıcının log'unda neden görünmüyor? Olası neden: deferred queue scene reload'da temizleniyor mu? Repro test öner."),
    ("audit-save-packedscene-feasibility",
     "Plan B fizibilite",
     "Test scene yarat: 256×256 MobileTerrain3D, height_data dolu. `PackedScene.pack(root)` + `ResourceSaver.save(packed, path)` ile save et. Sonuç .tscn'i incele: height_data alanı yazılmış mı? Plan B çalışıyor mu doğrula."),
    ("audit-save-restore-null-guard",
     "plugin.gd:1718 _restore_after_save",
     "Backup dict malformed (eksik 'node' veya 'height_data' key) olursa ne olur? Crash mı, silent skip mi?"),
    ("audit-save-multi-terrain",
     "plugin.gd:1576 backup collection",
     "Sahnede 2+ MobileTerrain3D varken: backup map node-keyed mi? Aynı .res path'e iki terrain yazıyor mu?"),
    ("audit-save-resourcesaver-error-codes",
     "node.gd:1167 ResourceSaver.save",
     "Hangi error code'lar return ediliyor? FILE_CANT_OPEN, FILE_CANT_WRITE handle ediliyor mu?"),

    # Chunk lifecycle (7)
    ("audit-chunk-dirty-propagation",
     "node.gd:2472 _mark_chunk_dirty",
     "Boundary cell mark'ları komşu chunk'a propagate ediliyor mu? Edge-of-map durumu doğru mu?"),
    ("audit-chunk-budget",
     "node.gd:_process adaptive budget",
     "4-64 budget hesabı: chunk sayısı çok büyükse rebuild fps'i nasıl etkiliyor?"),
    ("audit-chunk-tangent-fill",
     "node.gd:update_chunk_mesh tangent",
     "Vertex tangent +X sabit; eğimde normal mapping error magnitude ölç."),
    ("audit-chunk-multimesh-gc",
     "node.gd:garbage_collect_multimeshes",
     "Kullanılmayan MMI gerçekten silinmiş mi yoksa orphan node mu?"),
    ("audit-chunk-map-size-mid-rebuild",
     "node.gd:initialize_terrain",
     "Rebuild loop'u sırasında map_size değişirse?"),
    ("audit-chunk-sync-rebuild-limit",
     "node.gd:SYNC_REBUILD_CHUNK_LIMIT=256",
     "force_update_all'da limit doğru tetikleniyor mu?"),
    ("audit-chunk-resize-during-stroke",
     "node.gd:start_stroke + map_size setter",
     "Stroke sırasında map_size değişirse height_data uzunluk uyumu, brush footprint validity?"),

    # Brush / Sculpt (8)
    ("audit-brush-mask-fallback",
     "node.gd:_set_brush_mask + 2246 _is_in_brush",
     "Mask atanmış ama yüklenememişse fallback shape devreye giriyor mu?"),
    ("audit-brush-smooth-dirty-order",
     "node.gd:2377 _smooth_height",
     "**KNOWN BUG**: dirty mark stale height_data üzerinden. Doğrula ve fix öner."),
    ("audit-brush-erode-bounds",
     "node.gd:2461 _erode_height",
     "**KNOWN BUG**: lowest_idx bounds check eksik (negative veya >= map_size²). Doğrula."),
    ("audit-brush-flatten-cached-read",
     "node.gd:2338 _flatten_height",
     "Stale height_data[idx] read; cache yapılması performance + correctness için iyi."),
    ("audit-brush-terrace-clamp",
     "node.gd:2407 _terrace_height",
     "strength<0.2'de step=1 sabit. Kasıtlı ama dokümante edilmemiş — comment ekle öner."),
    ("audit-brush-noise-determinism",
     "node.gd:_noise_height + noise_gen",
     "Seed reset edilmediği için undo/redo'da farklı sonuç verir mi? Doğrula."),
    ("audit-brush-mask-decompress-leak",
     "plugin.gd:2074 _brush_mask_image",
     "**KNOWN BUG**: Mask swap'ında stale kalıyor. Reload pattern'i doğrula."),
    ("audit-brush-footprint-duplication",
     "node.gd:2312-2470 6 op",
     "6 height op'un %80 boilerplate'i. brush_system'e taşımak için ortak iterator API'sini tasarla."),

    # Paint / Splatmap (6)
    ("audit-paint-slot-bounds",
     "node.gd:2110 _paint_splatmap",
     "**KNOWN**: `> 3` yerine `>= 4`; 0 ≤ slot < 4 explicit range."),
    ("audit-paint-shared-ref",
     "node.gd:2210 splatmap_data = img.get_data()",
     "**KNOWN**: .duplicate() eksik. Shared reference test'i yaz."),
    ("audit-paint-null-update",
     "node.gd:2202 splatmap_texture_local.update",
     "**KNOWN**: null check yok. Race window doğrula."),
    ("audit-paint-tool-switch-cache",
     "node.gd:current_tool setter",
     "**NEW BUG**: Tool paint→sculpt geçişte `_splatmap_stroke_image` cache temizlenmiyor."),
    ("audit-paint-init-mid-stroke",
     "node.gd:_initialize_splatmap",
     "Stroke ortasında çağrılırsa? Set null guard zaten var mı? Doğrula."),
    ("audit-paint-slot5-silent-fail",
     "node.gd:_paint_splatmap RGBA cap",
     "Slot 5+ paint silent fail. MT-005 warn ekle öner."),

    # Foliage / Scatter (4)
    ("audit-foliage-spacing",
     "node.gd:_scatter_foliage object_min_spacing",
     "min_spacing > brush_radius silent no-op. Warn at start_stroke?"),
    ("audit-foliage-multimesh-resize",
     "node.gd:_get_or_create_multimesh + instance_count",
     "Undo sırasında instance_count drift? Race?"),
    ("audit-foliage-signal-emission",
     "node.gd:2553 foliage_placed.emit",
     "Her placement'ta emit ediliyor mu? Plugin signal dinleme pattern'i doğru mu?"),
    ("audit-foliage-transform-from-normal",
     "node.gd:_place_foliage_slope",
     "Eğimli yüzeylerde transform basis doğru mu? Up vector normal ile align mı?"),

    # Raymarch (3)
    ("audit-raymarch-iter-cap",
     "node.gd:1804 get_intersection_raymarch_persistent",
     "Adaptive `mini(8000, diag+cam_dist+100)` çok büyük map'lerde yeterli mi?"),
    ("audit-raymarch-edge-camera-below",
     "node.gd:1804 raymarch i==0",
     "Camera-below-terrain spurious hit guard tüm path'lerde var mı?"),
    ("audit-raymarch-binary-search-oob",
     "node.gd:1804 raymarch binary search",
     "OOB guard yeterli mi? End-of-march'ta last position bounds dışı mı?"),

    # Shader (4)
    ("audit-shader-uniform-binding",
     "node.gd:745 update_shader_textures",
     "Her uniform için doğru index map'liyor mu? terrain_textures.size() değişince consistent mi?"),
    ("audit-shader-blank-fallback-cache",
     "node.gd:_blank_textures dict",
     "Material swap'ta dict stale referans tutuyor mu?"),
    ("audit-shader-extraction-syntax",
     "node.gd:446 TERRAIN_SHADER",
     "264-satır inline shader → .gdshader dosyası. String escape sequence veya literal interpolation sorunu var mı?"),
    ("audit-shader-pbr-array-padding",
     "node.gd:_ready PBR array padding",
     "terrain_normal/roughness/ao/height/metallic/emission terrain_textures.size()'a paddingli mi her durumda?"),

    # Editor (6)
    ("audit-editor-input-stroke-order",
     "plugin.gd:1977 _forward_3d_gui_input",
     "**KNOWN BUG**: start_stroke() raymarch'tan ÖNCE → miss durumunda orphan cache."),
    ("audit-editor-brush-toggle-on-cursor",
     "plugin.gd:1449 _on_brush_toggle + 1495 _show_cursor_at_current_mouse",
     "Toggle-on'da cursor anında belirmesi tam test edildi mi?"),
    ("audit-editor-signal-double-connect",
     "plugin.gd:1770 _edit + 297 disconnect",
     "is_connected then connect pattern her yerde tutarlı mı?"),
    ("audit-editor-undo-redo-foliage",
     "plugin.gd:222 _commit_placement_undo",
     "Combined undo action build doğru mu? instance_count revert + set_instance_transform doğru index'lerde mi?"),
    ("audit-editor-dropdown-id-mapping",
     "plugin.gd:1439 _index_for_id",
     "Item reorder'da ID-based mapping bozulmuyor mu?"),
    ("audit-editor-asset-manager-rebuild",
     "plugin.gd:903 _refresh_manager_ui",
     "Her durumda doğru durumu yansıtıyor mu? Stale slot row?"),

    # General hazards (4)
    ("audit-general-stringname-subscript",
     "Tüm dosyalar",
     "`name[i]` veya `name.length()` her yerde String(name) cast'li mi? grep -rn 'name\\[' && grep -rn 'name\\.length()'."),
    ("audit-general-deferred-stale-capture",
     "Tüm call_deferred kullanımları",
     "Capture edilen argümanlar deferred çağrı zamanında stale olabilir mi?"),
    ("audit-general-large-range-budget",
     "Multi-MB array üzerinde range()",
     "1.6M element üzerinde range() bütçesiz iterasyon var mı?"),
    ("audit-general-image-lock-leftovers",
     "Tüm Image kullanımı",
     "Godot 3 `lock()/unlock()` kalıntısı var mı? `grep -rn 'lock()'`."),
]

assert len(audits) == 50, f"Audit count {len(audits)} != 50"

for name, context, task in audits:
    body = f"""
    Sen **{name}**. Manager'ından emir alırsın; kendi başına başlama.

    ## Bağlam
    {context}

    ## Görev
    {task}

    ## Çıktı
    Manager'a kısa rapor dön:
    ```
    finding: <bug var / yok>
    severity: CRITICAL | HIGH | MEDIUM | LOW
    file:line: <varsa>
    evidence: <quote 2-3 satır kod>
    recommendation: <bir cümle fix>
    ```

    Sen READ-ONLY'sin. Hiçbir dosya değiştirme; sadece oku ve raporla.
    """
    write(f"audit/{name}.md", md(name, f"Audit: {task[:80]}...", "Read, Grep, Glob, Bash", body, model="sonnet"))


# ============================================================
# 4. FIX WORKERS (50)
# ============================================================
fixes = [
    # Save fix (8)
    ("fix-save-plan-b-perform-resave",
     "save_orchestrator.gd YENİ DOSYA",
     "Plan B: `_perform_resave` içinde EditorInterface.save_scene() yerine PackedScene.pack(root) + ResourceSaver.save(packed, scene_path). Yeni dosya: `addons/mobile_terrain/editor/save_orchestrator.gd`. Plugin'in `_save_external_data`'sı tek satır olarak buraya delege etsin."),
    ("fix-save-suppress-flag-error-path",
     "node.gd:1167-1180 _externalize_data",
     "Hata çıkış path'inde `_suppress_external_path_setter = false` clear et."),
    ("fix-save-validate-property-cleanup",
     "node.gd:292 _validate_property",
     "Plan B ile redundant; sadece Inspector görünürlüğü için tut. Yorum güncelle: 'ineffective for save, kept for Inspector visibility'."),
    ("fix-save-restore-defensive-guards",
     "save_orchestrator.gd _restore",
     "Backup dict shape doğrula: has('node'), is_instance_valid(node), has('height_data') vs."),
    ("fix-save-error-catalog",
     "save_orchestrator.gd + persistence_system.gd",
     "TerrainDiagnostics.error(E_SAVE_PACK_FAILED) gibi MT-001..MT-099 kodlar yerleştir."),
    ("fix-save-strip-debug-prints",
     "plugin.gd + node.gd (save path'leri)",
     "Tüm `>>> [MobileTerrain3D Node]`, `=== [MobileTerrain3D]`, `[MobileTerrain3D]` print spam'ini sil. Sadece push_warning kalsın (gerçek hata)."),
    ("fix-save-multi-terrain-isolation",
     "save_orchestrator.gd",
     "Backup dict node UID-keyed. 2+ terrain'de çakışma yok."),
    ("fix-save-tests",
     "test/integration/save_roundtrip.gd YENİ",
     "Headless save roundtrip test: create 1280×1280 → save → assert .tscn<100KB, .res~6MB → reload → assert data restored."),

    # Refactor extraction (12)
    ("fix-extract-terrain-shader-to-gdshader",
     "node.gd:446-710 TERRAIN_SHADER + shaders/terrain.gdshader YENİ",
     "264-satır inline shader string → ayrı `.gdshader` dosyası. _setup_default_shader: `load(\"res://addons/mobile_terrain/shaders/terrain.gdshader\")`. const TERRAIN_SHADER sil."),
    ("fix-extract-chunk-system",
     "systems/chunk_system.gd YENİ",
     "node.gd: initialize_terrain, _create_chunk, update_chunk_mesh, _mark_chunk_dirty, force_update_all, garbage_collect_multimeshes, repurpose_multimesh_to, _get_or_create_multimesh, restore_multimeshes → ChunkSystem (Node3D olmak zorunda değil, RefCounted). Node bir instance composeluyor."),
    ("fix-extract-heightmap-system",
     "systems/heightmap_system.gd YENİ",
     "height_data storage, get_height (clamped), set_height, dirty propagation hooks → HeightmapSystem (RefCounted)."),
    ("fix-extract-brush-system",
     "systems/brush_system.gd YENİ",
     "_is_in_brush + brush_shape_falloff + mask sampling birleşmiş tek API: `iterate_footprint(center, radius, callback)`, `falloff_at(local_x, local_z) -> float`. Tek source of truth."),
    ("fix-extract-sculpt-ops",
     "systems/sculpt_ops.gd YENİ",
     "6 height op (modify/flatten/smooth/noise/terrace/erode) brush_system'in iterate_footprint'ini kullanır. %80 boilerplate yok edilir. Her op: static func, heightmap + brush + params girer."),
    ("fix-extract-splatmap-system",
     "systems/splatmap_system.gd YENİ",
     "_paint_splatmap, stroke cache, GPU sync, _initialize_splatmap → SplatmapSystem (RefCounted)."),
    ("fix-extract-foliage-system",
     "systems/foliage_system.gd YENİ",
     "_scatter_foliage, _place_foliage_slope → FoliageSystem (RefCounted). foliage_placed signal."),
    ("fix-extract-raymarch-system",
     "systems/raymarch_system.gd YENİ",
     "get_intersection_raymarch_persistent → RaymarchSystem (RefCounted)."),
    ("fix-extract-shader-system",
     "systems/shader_system.gd YENİ",
     "update_shader_textures, _get_or_create_blank_texture, _blank_textures cache, PBR slot binding → ShaderSystem (RefCounted)."),
    ("fix-extract-persistence-system",
     "systems/persistence_system.gd YENİ",
     "_externalize_data, _inline_data, _load_external_data_if_set → PersistenceSystem (RefCounted)."),
    ("fix-extract-editor-ui-modules",
     "editor/ui/*.gd YENİ (4 dosya)",
     "Toolbar / AssetManager / BrushPicker / BrushCursor → ayrı dosyalar. Her biri Control/MeshInstance3D extend eden ve composition'da kullanılan modül."),
    ("fix-extract-input-router",
     "editor/input_router.gd YENİ",
     "`_forward_3d_gui_input` dispatch logic → InputRouter (RefCounted). Plugin shell sadece event'i forward eder."),

    # Facade & wiring (6)
    ("fix-wire-node-facade",
     "node.gd YENİDEN YAZILIYOR",
     "~400 satıra in: tüm @export property'ler korunur. Subsistem instance'ları (chunk, heightmap, splatmap, brush, sculpt_ops, foliage, raymarch, shader, persistence) _ready'de yaratılır. Setter'lar subsisteme delege eder. **class_name MobileTerrain3D KORUNUR.**"),
    ("fix-wire-plugin-shell",
     "plugin.gd YENİDEN YAZILIYOR",
     "~150 satıra in: sadece EditorPlugin virtuals (_enter_tree, _exit_tree, _handles, _edit, _make_visible, _forward_3d_gui_input, _save_external_data). Tüm logic editor_plugin.gd / save_orchestrator.gd / input_router.gd / undo_recorder.gd'ye delege."),
    ("fix-wire-constants",
     "core/terrain_constants.gd YENİ",
     "Tüm const'lar (SYNC_BUILD_CHUNK_LIMIT, MAX_CHUNK_COUNT, AUTO_EXTERNALIZE_THRESHOLD, MIN_STATIONARY_INTERVAL, vd.) tek dosyada toplanır. class_name TerrainConstants."),
    ("fix-wire-diagnostics",
     "core/terrain_diagnostics.gd YENİ",
     "MT-001..MT-999 hata kodları katalog. static func error(code, args) / warn(code, args). Tüm push_error/push_warning bunun üzerinden geçer."),
    ("fix-wire-undo-recorder",
     "editor/undo_recorder.gd YENİ",
     "Plugin'den undo logic (heightmap_backup, splatmap_backup, placement_records, _ensure_backup_for_current_tool, _commit_placement_undo, _finalize_active_stroke) → UndoRecorder. Plugin shell sadece event'leri forward."),
    ("fix-wire-save-orchestrator",
     "Plugin shell ↔ save_orchestrator wiring",
     "`_save_external_data()` plugin shell'de tek satır: `save_orchestrator.save_with_externalized_terrains(get_editor_interface().get_edited_scene_root())`."),

    # Module 5-9 bug fixes (12)
    ("fix-bug-paint-slot-bounds",
     "splatmap_system.gd::paint",
     "Slot range: `if not (0 <= slot < 4): TerrainDiagnostics.warn(W_PAINT_SLOT_CAP, [slot]); return`."),
    ("fix-bug-paint-shared-ref-duplicate",
     "splatmap_system.gd::paint non-stroke path",
     "`splatmap_data = img.get_data().duplicate()`. Stroke path zaten cached, etkilenmez."),
    ("fix-bug-paint-null-update-guard",
     "splatmap_system.gd::paint GPU update",
     "if splatmap_texture_local != null and splatmap_texture_local.has_method('update'): splatmap_texture_local.update(img)."),
    ("fix-bug-paint-tool-switch-cache-clear",
     "node.gd facade::current_tool setter",
     "current_tool değişiminde splatmap_system._splatmap_stroke_image = null."),
    ("fix-bug-smooth-dirty-order",
     "sculpt_ops.gd::smooth",
     "temp_heights yaz → height_data = temp_heights ASSIGN → SONRA dirty mark loop'u. Yeni heightmap üzerinden mark."),
    ("fix-bug-erode-bounds",
     "sculpt_ops.gd::erode",
     "`if lowest_idx < 0 or lowest_idx >= map_size * map_size: continue` before nz/nx çevrim."),
    ("fix-bug-flatten-cached-read",
     "sculpt_ops.gd::flatten",
     "`var cur = height_data[idx]` cache, lerp formülünde reuse."),
    ("fix-bug-input-stroke-order",
     "input_router.gd",
     "start_stroke() çağrısı raymarch hit'ten SONRA. Miss durumunda hiç stroke açma."),
    ("fix-bug-brush-mask-decompress-leak",
     "brush_system.gd::_set_brush_mask",
     "Mask değiştiğinde `_brush_mask_image = null` clear (sonraki ilk kullanımda yeniden decompress)."),
    ("fix-bug-stringname-subscript-audit",
     "Tüm dosyalar",
     "`grep -rn 'name\\[\\|name\\.length()'` → her bulunan yerde `String(name)` cast. Audit raporundan exact line'ları al."),
    ("fix-bug-erode-resize-during-stroke",
     "sculpt_ops.gd::erode + brush_system.gd",
     "Brush iteration başlarken `var iter_map_size = map_size` snapshot al; ortada değişirse continue."),
    ("fix-bug-shader-blank-cache-invalidate",
     "shader_system.gd::set_material",
     "Material swap'ta `_blank_textures.clear()`."),

    # Test & QA (8)
    ("fix-qa-headless-godot-install",
     "test/setup_godot.sh YENİ",
     "Container'a Godot 4.6.2 headless idempotent kur: `which godot || (wget && unzip && ln -s)`. CI her oturum başında çağırır."),
    ("fix-qa-parse-check-script",
     "test/parse_check.sh YENİ",
     "Tüm .gd dosyalarını godot --script test/parse_check.gd ile parse-check et. Exit code 0/1."),
    ("fix-qa-unit-test-framework",
     "test/run_tests.gd + test/unit/*.gd YENİ",
     "Minimal GUT-style harness. Assert helper'lar (assert_eq, assert_ne, assert_true, assert_lt). Tek SceneTree script discovery."),
    ("fix-qa-test-heightmap-system",
     "test/unit/test_heightmap_system.gd",
     "get_height clamping, set_height boundary, dirty propagation test'leri."),
    ("fix-qa-test-brush-system",
     "test/unit/test_brush_system.gd",
     "iterate_footprint footprint area assertion, falloff edges, mask sampling test'leri."),
    ("fix-qa-test-sculpt-ops",
     "test/unit/test_sculpt_ops.gd",
     "6 op tek tek: modify+strength=1 → +falloff, flatten → target match, smooth → mean check, erode bounds, terrace step, noise determinism."),
    ("fix-qa-test-save-roundtrip",
     "test/integration/save_roundtrip.gd",
     "Create 1280×1280 → save → assert .tscn<100KB, .res~6MB → reload → assert data restored."),
    ("fix-qa-test-multi-terrain-save",
     "test/integration/multi_terrain_save.gd",
     "2 MobileTerrain3D'li sahne save/reload. Her terrain ayrı .res, name conflict yok."),

    # Polish (4)
    ("fix-polish-debug-print-purge",
     "addons/mobile_terrain/**/*.gd",
     "`grep -rE '^\\s*print\\(' addons/mobile_terrain/` → 0 match olana kadar tümünü sil. Stack trace gerektirebilecek yerlerde push_warning."),
    ("fix-polish-error-message-catalog",
     "core/terrain_diagnostics.gd + all sites",
     "Her push_error/push_warning MT-XXX kodu kullanıyor mu doğrula. Eksik olan yerlere kod ekle."),
    ("fix-polish-changes-md",
     "addons/mobile_terrain/CHANGES.md",
     "V22 entry: AAA refactor, Plan B save fix, module 5-9 bug fixes, debug print purge, diagnostics catalog."),
    ("fix-polish-plugin-version",
     "addons/mobile_terrain/plugin.cfg",
     "version=\"22.0\"."),
]

assert len(fixes) == 50, f"Fix count {len(fixes)} != 50"

for name, target, task in fixes:
    body = f"""
    Sen **{name}**. Manager'ından emir alırsın; kendi başına başlama.

    ## Hedef
    {target}

    ## Görev
    {task}

    ## Çıktı
    Manager'a kısa rapor dön:
    ```
    status: ok | failed
    files_modified: [list]
    lines_changed: ~N
    notes: <varsa kısa not>
    ```

    ## Kurallar
    - Her push_error/push_warning `TerrainDiagnostics.error/warn(CODE, args)` formatında.
    - Asla `print(...)` ekleme.
    - Yorumlar İngilizce, "neden" anlatır.
    - Edit yaparken eski Read'i atla — direkt Edit tool ile değiştir, sürpriz olmasın.
    - Değişiklikten sonra `godot --headless --script test/fixtures/parse_check/parse_check.gd` çalıştır, temizse OK döner.
    """
    write(f"fix/{name}.md", md(name, f"Fix: {task[:80]}...", "Read, Edit, Write, Bash, Grep, Glob", body, model="sonnet"))

print(f"Generated {1 + 7 + 50 + 50} agent definitions in {ROOT}")
