# MobileTerrain3D V21 — Handoff Dökümanı

> **Hedef okuyucu:** Claude Code veya başka bir AI assistant
> **Durum:** V21 development, son aktif sorun: scene `.tscn` save sırasında 26 MB inline veri sorunu (çözüm yarım kaldı)
> **Godot sürümü:** 4.6.2.stable.official, Mobile rendering method
> **Tarih:** May 2026

---

## 1. PROJE YAPISI

### Dosyalar
```
addons/mobile_terrain/
├── plugin.cfg                    # Version "21.0"
├── mobile_terrain_plugin.gd      # ~2160 lines, EditorPlugin
├── mobile_terrain_node.gd        # ~2630 lines, @tool extends Node3D, class_name MobileTerrain3D
├── mobile_terrain_data.gd        # 33 lines, class_name MobileTerrainData extends Resource (external storage)
├── fix_texture_imports.gd        # ~390 lines, texture import workflow helper
├── CHANGES.md                    # Versiyon notları
└── brushes/                      # 20 adet PNG mask (256×256 grayscale)
```

### Kullanıcı dili
Türkçe konuşuyor. UI string'leri Türkçe. Kullanıcı app developer, mobile-target.

### Çalışma dizini (geliştirme sırasında)
- Source: `/home/claude/output/mobile_terrain_v20/addons/mobile_terrain/` (legacy v20 isim, içerik V21)
- Final ZIP: `/mnt/user-data/outputs/MobileTerrain3D_V20.zip`
- User project: `/mnt/user-data/uploads/yeni-oyun-projesikdkdod.zip`
- Reference textures: `/mnt/user-data/uploads/forrest_ground_01_diff_1k.webp`

---

## 2. AKTİF SORUN — 26 MB .tscn SAVE BUG

### Belirti
Kullanıcı 1254×1254 (sonra 1280×1280 olarak round'lanıyor) heightmap import ediyor. `Ctrl+S` sonrası Godot uyarısı:
```
The text-based scene at path "res://main.tscn" is large on disk (26.57 MiB),
likely because it has embedded binary data.
```

### Neden
`@export var height_data: PackedFloat32Array` ve `@export var splatmap_texture_local: ImageTexture` — 1280² = 1.6M float × 4 byte = 6.4 MB heightmap + 6.4 MB splatmap RGBA bytes, base64 encoded `.tscn` text'inde → 26 MB.

### V21'de denenen 3 yaklaşım ve durumları

**Yaklaşım 1: Plain `var` + `_get_property_list`** ❌ TERK EDİLDİ
- Plain `var height_data` (export'suz) + `_get_property_list` override ile property eklemek
- Godot 4.2'de [issue #87636](https://github.com/godotengine/godot/issues/87636): `_get_property_list` ve plain var aynı isimde → double-listing
- Terk edildi

**Yaklaşım 2: `@export var` + `_validate_property` USAGE flag** ❌ ÇALIŞMIYOR
- `@export var height_data` ile property'yi Godot'a kabul ettir
- `_validate_property` ile USAGE flag'ini dinamik değiştir:
  - `external_data_path == ""` → `PROPERTY_USAGE_DEFAULT` (inline save)
  - `external_data_path != ""` → `PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_SCRIPT_VARIABLE` (NOSTORE)
- **Log'dan kanıt**: `_validate_property` çağrılıyor, USAGE değişiyor, AMA Godot 4.6 hâlâ inline yazıyor
- Hipotez: `_validate_property` `_save_external_data` hook'undan **ÖNCE** çağrılıyor; biz path'i `_save_external_data`'da set ettiğimizde **çok geç**

**Yaklaşım 3: Backup + wipe + re-save (AKTİF, henüz doğrulanmadı)** ⚠️ TEST EDİLMEDİ
- Strateji:
  1. `_save_external_data` (EditorPlugin virtual) tetiklenir — bu Godot'un scene serialize'inden SONRA çalışır
  2. `.res` dosyasını ResourceSaver ile yaz
  3. `terrain.height_data = PackedFloat32Array()` (empty), `terrain.splatmap_texture_local = null` — in-memory **wipe**
  4. `_suppress_next_save_hook = true` flag set
  5. `call_deferred("_perform_resave", scene_path, backups)` — ikinci `EditorInterface.save_scene()` tetikle
  6. İkinci save'in hook çağrısı flag'i görüp suppress eder
  7. `call_deferred("_restore_after_save", backups)` ile in-memory restore
- **Son test sonucu**: Parse error vardı (`name` StringName'i subscript'lenemez), düzeltildi
- **Kullanıcı yeni ZIP'i test etmedi**, durum bilinmiyor

### Plan B (eğer Yaklaşım 3 başarısız olursa)
`EditorInterface.save_scene()` yerine **manuel `PackedScene.pack()` + `ResourceSaver.save()`**:
```gdscript
var packed := PackedScene.new()
packed.pack(edited_root)
ResourceSaver.save(packed, scene_path)
```
Bu engine'in save flow'unu tamamen bypass eder, deterministic.

---

## 3. EXTERNAL STORAGE MİMARİSİ

### Resource class
```gdscript
# mobile_terrain_data.gd
@tool
class_name MobileTerrainData
extends Resource
@export var height_data: PackedFloat32Array
@export var map_size: int = 0
@export var splatmap_bytes: PackedByteArray
@export var splatmap_size: int = 0
```

### Node properties (external storage)
```gdscript
@export_file("*.res") var external_data_path: String = "" : set = _set_external_data_path
@export var height_data: PackedFloat32Array          # USAGE dynamic via _validate_property
@export var splatmap_texture_local: ImageTexture     # USAGE dynamic via _validate_property
@export var click_to_externalize: bool = false : set = _externalize_data
@export var click_to_inline: bool = false : set = _inline_data
const AUTO_EXTERNALIZE_THRESHOLD := 262144  # 512 × 512
```

### Setter cascade guard flag'leri
Internal write'ların setter recursion'ı tetiklememesi için:
```gdscript
var _suppress_external_path_setter: bool = false
var _suppress_chunk_size_setter: bool = false
```
Plugin tarafında:
```gdscript
var _suppress_next_save_hook: bool = false  # save re-entry guard
```

### Plugin hook
```gdscript
func _save_external_data() -> void:
    if _suppress_next_save_hook:
        _suppress_next_save_hook = false
        return
    # ... collect terrains, write .res, wipe inline, trigger re-save
```

---

## 4. V21 BOYUNCA YAPILAN DÜZELTMELER (özet)

### Round 1-7 audit (~42 bug)
- Strength scaling rationalization (slider 0.1-2.0, per-tool internal multipliers)
- ID-based dropdowns (was index-based; broke if items reordered)
- Splatmap UV off-by-one (`/ map_size` → `/ max(1, map_size-1)`)
- Foliage signal duplicate guard (`is_connected` check)
- Splatmap stroke cache (avoid per-dab 256KB allocation)
- Multi-node stroke corruption (`_edit` finalizes old node before switching)
- Brush master toggle (was always-on)
- Object scatter mode (was single-instance-per-dab)
- Unified `_finalize_active_stroke` (5 call sites)

### Performance (1254×1254 map sorunu)
- EXR import: bulk `get_data()` instead of 1.57M `get_pixel` calls (30-50× faster)
- Chunk lifecycle: deferred build for >256 chunks
- `_set_map_size`: auto-bump chunk_size for large maps (`[64, 128, 256, 512, 1024]`)
- `update_chunk_mesh`: pre-allocate arrays, inline `get_height`, bulk tangent fill
- `_process`: adaptive budget (4-64 chunks/frame)
- `force_update_all`: deferred for large maps
- **CRITICAL FIX**: `_process` editor-only gate kaldırıldı (runtime'da büyük map terrain BLANK kalıyordu!)

### Raymarch (Modül #3 audit)
- Adaptive max iterations (`mini(8000, diag+cam_dist+100)`) — was hardcoded 500
- Early termination y threshold `-200` (was -100)
- Camera-below-terrain edge case (i==0 spurious hit guard)
- Binary search OOB guard
- Inline neighbour reads (no `get_height` call overhead)

### Stroke lifecycle (Modül #4 audit)
- `_initialize_splatmap` başında `_splatmap_stroke_image = null` (map_size mid-stroke change protection)
- `end_stroke` `splatmap_data = get_data().duplicate()` (shared reference protection)

### Brush kursor sorunu
- Toggle on'da cursor anında belirmesi için `_show_cursor_at_current_mouse` eklendi
- Cached camera + mouse position (EditorInterface API roulette'i bypass için)

---

## 5. KULLANIM KISITLAMALARI VE TUZAKLAR

### Godot 4.6'da bilinen quirk'ler
1. `Node.name` `StringName` tipinde, `name[i]` subscript ÇALIŞMAZ → `String(name)` cast şart
2. `_validate_property` save serialization'ını etkilemiyor olabilir (deneysel)
3. `NOTIFICATION_EDITOR_PRE_SAVE` Node'lara fire EDİLMEZ (sadece Resource'lara) — Godot forum onayladı
4. `_save_external_data` Godot 4.6'da scene serialize'den **SONRA** çağrılıyor (deneysel kanıt log'dan)
5. `EditorInterface.save_scene()` Godot 4.6'da çalışıyor mu? Test edilmedi

### Setter cascade tuzakları
- `chunk_size = X` → `_set_chunk_size` → `initialize_terrain` cascade
- `map_size = X` → `_set_map_size` → auto-bump chunk_size + `_initialize_splatmap` + `initialize_terrain`
- `external_data_path = X` → `_set_external_data_path` → `_load_external_data_if_set` + `initialize_terrain` + `update_shader_textures`
- **Internal write'larda suppress flag'leri SÜREKLİ kullan**

### Map_size invariants
- `map_size % chunk_size == 0` (sıkı garanti, `_align_to_chunks` enforces)
- `map_size >= chunk_size` (clamp inside `_align_to_chunks`)
- `chunk_size >= 1` (clamp inside `_set_chunk_size`)
- `chunk_size <= map_size` (clamp inside `_set_chunk_size`)

### Threshold sabitleri
```gdscript
const SYNC_BUILD_CHUNK_LIMIT := 256        # >256 chunks → deferred build
const SYNC_REBUILD_CHUNK_LIMIT := 256      # force_update_all'da
const MAX_CHUNK_COUNT := 1024              # auto-bump trigger
const AUTO_EXTERNALIZE_THRESHOLD := 262144 # 512² cells, auto-externalize trigger
const MIN_STATIONARY_INTERVAL := 0.04      # stroke throttle
const MIN_OBJECT_INTERVAL := 0.08          # foliage scatter throttle
```

---

## 6. ŞU AN AKTİF DEBUG TRACE'LERİ

Plugin enable'da:
```
=== [MobileTerrain3D] Plugin _enter_tree() FIRED ===
[MobileTerrain3D] If you see this, the plugin is loaded.
[MobileTerrain3D] On scene save, you should see _save_external_data() fire too.
```

Scene save sırasında BEKLENEN (Yaklaşım 3 çalışırsa):
```
=== [MobileTerrain3D] _save_external_data() FIRED ===
[MobileTerrain3D] Edited root: ...
[MobileTerrain3D] Found 1 MobileTerrain3D node(s) in the scene.
[MobileTerrain3D] '...': height_data.size=N, threshold=262144, qualifies=true, path='...', path_set=true/false, res_missing=false
[MobileTerrain3D] Auto-externalising '...' (N cells) to .res file...
>>> [MobileTerrain3D Node] _externalize_data() called for '...'
[MobileTerrain3D] ResourceSaver.save SUCCESS for 'res://..._terrain.res'.
[MobileTerrain3D] '...': backing up N cells, clearing in-memory for re-save...
[MobileTerrain3D] Triggering second save_scene to write small .tscn (...)...
=== [MobileTerrain3D] _save_external_data() RETURNING ===
=== [MobileTerrain3D] _perform_resave() FIRED for '...' ===
[MobileTerrain3D] save_scene() returned: 0
=== [MobileTerrain3D] _perform_resave() DONE (save_succeeded=true) ===
=== [MobileTerrain3D] _save_external_data() FIRED ===
[MobileTerrain3D] Suppressed (this is our re-save pass). Skipping externalise; restore queued.
=== [MobileTerrain3D] _restore_after_save() FIRED with 1 backup(s) ===
```

Debug print'lerin yerleri:
- `_save_external_data` (plugin.gd ~line 1576)
- `_perform_resave` (plugin.gd ~line 1690)
- `_restore_after_save` (plugin.gd ~line 1730)
- `_externalize_data` (node.gd ~line 1015)
- `_enter_tree` (plugin.gd ~line 103)

**Production'a hazırlanırken bunlar temizlenmeli** — şu an aktif sorunu debug ediyoruz.

---

## 7. CLAUDE CODE İÇİN GÖREVLER (öncelik sırası)

### Görev 1: 26 MB sorununu KESİN ÇÖZ ⚠️ KRİTİK
Kullanıcının paylaştığı en son log:
```
=== [MobileTerrain3D] _save_external_data() FIRED ===
[MobileTerrain3D] '...': height_data.size=1638400, threshold=262144, qualifies=true, path='', path_set=false, res_missing=false
[MobileTerrain3D] Auto-externalising '...' (1638400 cells) to .res file...
[MobileTerrain3D] ResourceSaver.save SUCCESS for 'res://main_MobileTerrain3D_terrain.res'.
[MobileTerrain3D] '...': backing up 1638400 cells, clearing in-memory for re-save...
[MobileTerrain3D] Queued 1 node(s) for post-save restore.
=== [MobileTerrain3D] _save_external_data() RETURNING ===
=== [MobileTerrain3D] _restore_after_save() FIRED with 1 backup(s) ===
```
ANCAK main.tscn hâlâ 26 MB. `_perform_resave` ve ikinci `_save_external_data() FIRED` log'da YOK → re-save tetiklenmemiş veya kullanıcının log'u kısaltılmış.

**Yapılacak:**
1. Kullanıcıdan log'un TAM hali al — özellikle `_perform_resave()` blok'unu görmek lazım
2. Eğer `save_scene()` çalışmıyorsa Plan B'ye geç:
   ```gdscript
   func _perform_resave(scene_path: String, backups: Array) -> void:
       var ei := get_editor_interface()
       var root: Node = ei.get_edited_scene_root()
       var packed := PackedScene.new()
       var err := packed.pack(root)
       if err == OK:
           ResourceSaver.save(packed, scene_path)
       call_deferred("_restore_after_save", backups)
   ```
3. `_suppress_next_save_hook` flag'i Plan B'de gereksiz — `ResourceSaver.save(PackedScene)` `_save_external_data`'i tetiklemez

### Görev 2: Debug print'leri temizle
- Aktif sorun çözüldükten sonra, tüm `print("[MobileTerrain3D]...")` ve `print(">>>...")` ve `print("===...")` satırlarını kaldır
- `push_warning` mesajları kalabilir (sadece gerçekten hata durumlarında)
- Kullanıcının `print()` spam'inden hoşlanmadığı log'lardan belli

### Görev 3: Modül auditine devam et (Modül #5-9)
Audit henüz tamamlanmadı. Şu modüller incelendi:
- ✅ Modül #1: External storage (31 sorun, 12 düzeltildi)
- ✅ Modül #2: Initialize terrain + chunk lifecycle (20 sorun, 9 düzeltildi)
- ✅ Modül #3: Raymarch (15 sorun, 5 düzeltildi)
- ✅ Modül #4: Stroke lifecycle (kısmi, 2 düzeltildi)
- ❌ Modül #5: Paint splatmap (`_paint_splatmap`, ~line 2106)
- ❌ Modül #6: Brush algorithms (`_modify_height`, `_flatten_height`, `_smooth_height`, `_noise_height`, `_terrace_height`, `_erode_height`)
- ❌ Modül #7: Shader & material (`TERRAIN_SHADER` const, `update_shader_textures`)
- ❌ Modül #8: Foliage/scatter (`_scatter_foliage`, `_place_foliage_slope`)
- ❌ Modül #9: Plugin UI/input handling (`_forward_3d_gui_input`, etc.)

Her modül için kontrol et:
- Logic correctness
- Edge cases (empty data, oversized values, mid-operation state changes)
- Race conditions (Godot single-thread olduğu için çoğu güvenli ama callback re-entrancy var)
- Memory leaks (shared references, queue_free vs free)
- Cross-module consistency (setter cascade'leri uyumlu mu)

### Görev 4: Brush kursor toggle-on edge case
Kullanıcı bir önceki turda "fırçayı kapattım ama açınca çalışmıyor" dedi. `_show_cursor_at_current_mouse` eklendi ama tam test edilmedi. Plan B Görev 1 sonrası test et.

### Görev 5: Performance regresyon kontrolü
Modül #3'te raymarch'a `get_height` → inline indeksleme yapıldı. Brush stroke'unun gerçek hızını profile et. Eğer regresyon varsa rollback.

---

## 8. KULLANICI İLE İLETİŞİM STİLİ

### Kullanıcı tercih ettiği üslup
- Türkçe konuşur, kısa cümleler kullanır
- Türkçe UI string'lerini referans eder: "Fırça AÇIK", "Yükselt", "Düzleştir", "map_size ayarla"
- Sistemli audit'leri sever ("kritik dev hata taraması", "spesifik spesifik ilerleyelim ki atlamayalim")
- Önce-sonra açıklamalı, neden yapıldığını açıklayan fix'ler ister
- Log paylaşır ve karşılığında kesin tanı bekler

### Kullanıcı şu an SİNİRLİ
Son mesaj: "Bizim ana hata düzeldi mi artık MB sorunu görmek istemiyorum"
→ Çok turda denenmiş, hâlâ çözülmemiş. **Bu sorunu KAPAT, başka şeye geçme**.

### Cevap formatı
- Mobile UI'da (kısa ekran, az formatting)
- Önce direkt cevap, sonra detaylar
- Kod blokları minimal
- Bullet list ok ama uzun olmasın
- Test sıralı talimatlar (numaralı)

---

## 9. TEKNİK BORÇ NOTLARI

### Çift initialize_terrain çağrısı
`_ready` editor mode'da `_load_external_data_if_set` → cascade `initialize_terrain` → sonra `call_deferred("initialize_terrain")` tekrar. Performance tradeoff, henüz fix yok.

### Splatmap sınırı: 4 slot
RGBA8 splatmap → max 4 texture slot. Daha fazla için secondary splatmap gerekir. UX olarak slot 5+ paint silent fail (cap'lendiği için artık olmaz).

### Range(500) raymarch (eski hardcoded)
Modül #3'te düzeltildi (adaptive). Kullanıcı henüz test etmedi.

### Tangent calc accuracy
Vertex tangent'ları world +X olarak sabit. Eğimli yüzeylerde küçük normal-mapping hatası. SurfaceTool ile per-vertex tangent hesabı daha doğru ama 10× yavaş. Mevcut yaklaşım pragma.

### `_terrace_height` low-strength quirk
`max(1.0, strength*5)` → strength < 0.2 ise step=1.0 sabit. Kasıtlı (düşük strength'te bile gözle görülür efekt için).

### Çok büyük map'ler (16K+)
`MAX_CHUNK_COUNT = 1024` cap var ama 16K map'te chunk başına 4M vertex → hâlâ ağır. Kullanıcı için "extreme" uyarısı veriyor.

---

## 10. TEST CHECKLIST (sırasıyla)

Aktif sorun çözüldükten sonra full smoke test:

- [ ] **Sahne yeni**: MobileTerrain3D ekle → görünür mi, default chunk 32, map 256
- [ ] **Map size değiş**: 1280 yaz → auto-bump chunk 64, deferred meshing log
- [ ] **EXR import**: 1280×1280 EXR import → height görünmeli, sonra externalize prompt
- [ ] **Save**: Ctrl+S → main.tscn < 100KB, .res ~6MB
- [ ] **Re-open**: Sahneyi kapat-aç → terrain restore, render normal
- [ ] **Sculpt**: Yükselt/Alçalt fare basılı, undo/redo, brush mask
- [ ] **Paint**: Boya tool, 4 slot, splatmap görünmeli
- [ ] **Object scatter**: Obje tool, mesh assign, scatter density slider
- [ ] **Brush toggle off/on**: Cursor anında belirmeli (mouse hareketsiz)
- [ ] **Multi-terrain**: Sahnede 2+ MobileTerrain3D → her birine ayrı .res
- [ ] **Resize during stroke**: Paint sırasında map_size değiş → corruption olmamalı
- [ ] **Undo across map_size**: Resize sonrası Ctrl+Z → height_data eski boyuta dönmeli

---

## 11. KOD KONVENSİYONLARI

- Tab indent (4-space görünür)
- Comment'ler İngilizce
- `V21 FIX:` / `V20 FIX (#N):` prefix'leri ile fix kanıt zinciri
- Yorumlarda "neden" anlatılır, "ne" değil (kod kendini açıklar)
- push_warning sadece kullanıcı-actionable durumlarda
- print sadece debug için (production'da çıkar)
- Setter'lar **mutlaka** clamp + warning ile invalid input'u kabul edilebilir hale getirir, throw etmez

---

## 12. SON SÜRÜM ZIP VE NEREDE

ZIP yolu sabit: `/mnt/user-data/outputs/MobileTerrain3D_V20.zip`

Build komutu:
```bash
cd /home/claude/output/mobile_terrain_v20
rm -f /mnt/user-data/outputs/MobileTerrain3D_V20.zip
zip -rq /mnt/user-data/outputs/MobileTerrain3D_V20.zip addons/
```

Son syntax check (parse error olmadığını doğrula):
```bash
cd /home/claude/output/mobile_terrain_v20/addons/mobile_terrain
python3 -c "
import re
for fname in ['mobile_terrain_node.gd', 'mobile_terrain_plugin.gd']:
    with open(fname) as f: content = f.read()
    funcs = re.findall(r'^func ([_a-zA-Z]\w*)', content, re.M)
    seen = set(); dups = [f for f in funcs if f in seen or seen.add(f)]
    print(f'{fname}: {len(content.splitlines())} lines, {len(funcs)} functions, {len(dups)} dups')
"
```

---

## 13. ÖNCELİKLİ SORUN ÖZETİ — "TL;DR"

**Sorun:** `main.tscn` 26 MB inline binary data ile şişiyor.

**Sebep:** `@export var height_data: PackedFloat32Array` 1.6M float'u .tscn'e base64 yazıyor.

**Denenen çözüm (henüz doğrulanmadı):**
1. EditorPlugin `_save_external_data` hook tetiklenir (KANITLI: log'da `FIRED` mesajı var)
2. Hook .res yazar (KANITLI: `ResourceSaver.save SUCCESS`)
3. Hook in-memory wipe yapar (KANITLI: `backing up... clearing`)
4. Hook `call_deferred("_perform_resave", ...)` (LOG'DA GÖRÜNMÜYOR — kullanıcının log'u kesik olabilir)
5. `_perform_resave` `EditorInterface.save_scene()` çağırır (TEST EDİLMEDİ)
6. İkinci save flag-suppressed çalışır → küçük .tscn (TEST EDİLMEDİ)

**Sonraki adım:**
- Kullanıcıdan TAM log al, özellikle `_perform_resave()` ve ikinci `_save_external_data() FIRED` mesajlarını gör
- Eğer `save_scene()` çalışmıyorsa Plan B: manuel `PackedScene.pack` + `ResourceSaver.save(packed_scene, path)`

**Test soruları:**
- `save_scene()` Godot 4.6'da exists mi? `has_method` check var, ama exists ama no-op mı?
- `_save_external_data` save_scene'in tetiklediği save sırasında tekrar tetikleniyor mu? Yoksa engine optimize edip ikinci hook'u atlıyor mu?

**Plan B kodu hazır (test edilmedi):**
```gdscript
func _perform_resave(scene_path: String, backups: Array) -> void:
    var ei := get_editor_interface()
    if ei == null:
        _suppress_next_save_hook = false
        _restore_after_save(backups)
        return
    var root: Node = ei.get_edited_scene_root()
    if root == null:
        _suppress_next_save_hook = false
        _restore_after_save(backups)
        return
    var packed := PackedScene.new()
    var pack_err := packed.pack(root)
    if pack_err == OK:
        var save_err := ResourceSaver.save(packed, scene_path)
        print("[MobileTerrain3D] PackedScene save returned: %s" % save_err)
    else:
        print("[MobileTerrain3D] PackedScene.pack failed: %s" % pack_err)
    _suppress_next_save_hook = false
    call_deferred("_restore_after_save", backups)
```

---

## 14. EN SON KARŞILAŞILAN PARSE ERROR (düzeltildi)

```
Parse Error: Cannot use subscript operator on a base of type "StringName".
mobile_terrain_node.gd:1129
```

Sebep: `Node.name` Godot 4'te `StringName`, `name[i]` çalışmıyor.
Düzeltme: `var name_str: String = String(name)` cast + `name_str[i]` kullan.

Aynı pattern başka yerlerde var mı kontrol et:
```bash
grep -rn "name\[\|name\.length()" mobile_terrain_*.gd
```

---

**Dökümanın sonu. Şanslar, Claude Code!**
