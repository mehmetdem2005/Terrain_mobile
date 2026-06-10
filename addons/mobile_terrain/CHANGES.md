# MobileTerrain3D — Changelog

## 22.1.0 (2026-06-10) — TKT-010 denetim onarımları

### Düzeltildi
- **Eşya yerleştirme (S1, veri kaybı):** path'siz mesh'ler (BoxMesh vb.) .tscn
  ve .res'e ayrı kopya gömüldüğünden reload sonrası registry çatallanıyor,
  GC yüklenen yerleştirmeleri siliyordu. Restore artık .res kopyasını
  asset_meshes'teki .tscn kopyasıyla yeniden birleştiriyor
  (`_resolve_restored_mesh`, slot indeksi kaydı, GC path-toleransı).
  Regresyon: `test_object_identity.gd` (eski kodda 3 failure ile doğrulandı).
- Boş "Terrain Place Objects" undo aksiyonu (hayalet Ctrl+Z slotu) artık
  oluşmuyor; küçülmüş multimesh için bozucu restore kaydedilmiyor
  (undo_recorder A2/A3 + 2 yeni test).
- Texture slotu silinince kalan slotların tiling/normal/roughness/AO
  değerlerinin kayması (4 skaler PBR dizisi silmede atlanıyordu).
- Plugin kapatılırken aktif stroke finalize edilmiyor, undo aksiyonu askıda
  kalıyordu; `_finalize_active_stroke` freed-node'a karşı da korumalı.
- `_make_visible(false)` placement_initial_counts'u da temizliyor.

### Performans (5 × P1)
- Smooth/erode: dab başına 6.5 MB tam-harita kopyası → footprint-yerel tampon.
- Paint: dab başına tam splatmap GPU upload'u → 0.1s birleştirme + stroke
  sonu flush (163 MB/s → ~10 Hz).
- place_one: O(n²) RS transform kopyası → tek buffer oku/yaz.
- Fırça imleci: motion başına ~2.5K çağrı → 30 Hz rate-cap.
- Undo + editör LOD çifte tam-rebuild dalgası → backlog > 128 iken LOD atlar.

## 22.0.0 (2026-06-10)

### Değişti
- Sürümleme SemVer 2.0.0 formatına geçti: `22.0` → `22.0.0` (davranış
  değişikliği yok; bundan sonra sahne formatını kıran değişiklik = MAJOR,
  geriye uyumlu özellik = MINOR, bug fix = PATCH).

### Eklendi (geliştirme altyapısı, eklenti davranışı aynı)
- Kurumsal standart yönetişimi: `docs/STANDARDS.md` (40 standart, projeye
  uyarlanmış) + 7 skill (`.claude/skills/`) + `scripts/validate_skills.sh`
  (skill yapı sözleşmesi denetçisi) + `scripts/release_build.sh` (SLSA L1
  provenanslı release build: zip + SHA256SUMS + provenance.json + SBOM).
- Ajan yetki matrisi: `docs/AGENT_AUTHORITY.md` (108 ajan, R1-R4 risk sınıfı,
  5/5 yönetişim kontrolü temiz).

---

# MobileTerrain3D V22 — AAA Architecture & Deterministic Save

V21'den V22'ye geçişte iki büyük değişiklik:

## 26 MB sahne save bug — **kesin çözüm (Plan B)**

Önceki "Approach 3" yaklaşımı `EditorInterface.save_scene()`'i deferred re-entry içinde tetikliyordu; Godot 4.6'da bu re-entry no-op kalıyordu ve `.tscn` 26 MB inline base64 olarak yazılıyordu.

V22 Plan B: `_save_external_data` artık `PackedScene.pack(edited_root)` + `ResourceSaver.save(packed, scene_path)` ile sahneyi kendi yazıyor. `EditorInterface` bypass edildi, re-entry yok, suppress flag dansı yok. Determinist.

**Kanıt** (`test/integration/save_roundtrip.gd` headless test):
- Inline (eskisi): 5.27 MB `.tscn`
- External (V22): **358 bytes** `.tscn` + 6.25 MB `.res`

Headless smoke test her CI çalıştığında doğrular.

## Modül 5-9 bug sweep

Audit (3 paralel Explore agent) yeni bug'lar buldu:

- **plugin.gd:1977** — `_forward_3d_gui_input`: `start_stroke()` raymarch'tan ÖNCE çağrılıyordu. Click off-terrain'de stroke açılıp kapanmıyordu → paint cache leaked. **Fix**: stroke açma artık raymarch hit'inden SONRA.
- **node.gd:2202** — `splatmap_texture_local.update(img)` null guard yoktu. **Fix**: defensive `!= null` check.
- **node.gd:2210** — `splatmap_data = img.get_data()` paylaşılan referans olabilir. **Fix**: `.duplicate()` ekledi.
- **node.gd:2110** — paint slot range mesajsız reddediyordu. **Fix**: `0 ≤ slot < 4` explicit + MT-005 warn.
- **node.gd:97** — `current_tool` setter yoktu; tool değişiminde paint stroke cache ölü-referans kalıyordu. **Fix**: setter eklendi, cache null'lanıyor.

## Debug print purge

`>>> [MobileTerrain3D Node]`, `=== [MobileTerrain3D]` ve `[MobileTerrain3D]` print spam'i tamamen kaldırıldı. Kullanıcı-actionable mesajlar `push_warning("MT-XXX: ...")` formatına geçirildi.

## Diagnostics catalog

Tüm uyarı/hata mesajları artık `MT-XXX` (errors) ve `MT-WXX` (warnings) kodları ile başlıyor:

- `MT-001` PackedScene.pack failed
- `MT-002` ResourceSaver.save failed
- `MT-005` paint slot out of range
- `MT-W03` texture slot cap (4 limit)
- `MT-W04..W09` asset manager + externalize feedback

## AAA mimari refactor (V22 devam ediyor)

V22 ayrıca monolit `mobile_terrain_node.gd` (2636 satır) + `mobile_terrain_plugin.gd` (2160 satır) yapısını katmanlı modüllere ayırıyor:

```
addons/mobile_terrain/
├── core/        # constants, diagnostics, data resource
├── systems/     # heightmap, chunk, brush, splatmap, foliage, raymarch, shader, persistence
├── editor/      # save_orchestrator, input_router, undo_recorder, ui/*
├── shaders/     # terrain.gdshader (inline'dan çıkarıldı)
└── brushes/     # PNG masks (dokunulmadı)
```

Mevcut `class_name MobileTerrain3D` ve tüm `@export` property'ler korunuyor; mevcut sahneler kırılmıyor. Facade pattern: node + plugin entrypoint'leri ince shell'ler, sistem ilçesine delege ediyor.

Ayrıca `.claude/agents/` altında **108 alt-agent tanımı** kuruldu (1 orkestratör + 7 yönetici + 50 audit + 50 fix). Bu kurulum kullanıcının kod altyapısında değil; tüm refactor pipeline'ını paralel agent'larla sürdürmeyi mümkün kılıyor.

---

# MobileTerrain3D V21 — Full PBR Slot System

V20.1'de terrain ekrana geldi ama beyazımsı/düz görünüyordu. Sebep: shader sadece düz albedo veriyordu, normal/roughness/AO yoktu → PBR pipeline'ın gerektirdiği surface detail eksik.

V21 bunu gideriyor. Her texture slot'u artık 4 map'i kabul ediyor:

- **Albedo** (renkli diffuse) — zorunlu
- **Normal** — surface detayı, ışıklandırma derinliği
- **Roughness** — bazı yerler parlak, bazı yerler mat
- **AO** — kenar gölgeleri, derinlik

## V21 yeni özellikler

### 🎨 PBR slot sistemi
Shader tamamen yeniden yazıldı. Her splatmap kanalı (R/G/B/A) bir slot'u kontrol ediyor; her slot'un kendine ait 4 map'i var. Tüm map'ler aynı splatmap ağırlığı ile blend'leniyor — albedo nereye gidiyorsa normal/roughness/AO da oraya gidiyor.

Shader uniform'ları:
- `tex_a_0..3` — albedo (sRGB)
- `tex_n_0..3` — normal (tangent-space, OpenGL/Y+)
- `tex_r_0..3` — roughness (linear, R kanalı)
- `tex_ao_0..3` — ambient occlusion (linear, R kanalı)

### 🔍 Otomatik kardeş tespit
Asset Manager'da her slot panel'inde **🔍 Tespit** butonu var. Albedo doluyken bas, addon dosya isminden marker çıkarıp aynı klasörde kardeş map'leri bulup dolduruyor:

Tanıdığı marker'lar:
- Diffuse: `_diff`, `_diffuse`, `_albedo`, `_basecolor`, `_color`, `_col`
- Normal: `_nor_gl` (tercihli), `_nor_dx`, `_norm`, `_normal`, `_nrm` 
- Roughness: `_rough`, `_roughness`, `_rgh`
- AO: `_ao`, `_occlusion`, `_ambient_occlusion`

Örnek: `forrest_ground_01_diff_1k.png` seçili → 🔍 bas:
- `forrest_ground_01_nor_gl_1k.png` bulundu ✓ Normal slot'una atandı
- `forrest_ground_01_rough_1k.png` bulundu ✓ Roughness'a
- `forrest_ground_01_ao_1k.png` bulundu ✓ AO'ya

DX vs GL normal: `_nor_gl` Godot'un beklediği convention. `_nor_dx` da algılanır ama Godot'un Y koordinatı ters görünebilir; gerekirse Inspector'dan ilgili texture'ın Import sekmesinde **Normal Map → Invert Y** açabilirsin.

### 🎚 Global PBR kontrolleri
Inspector'da yeni @export'lar:
- **normal_strength** (0-2, default 1.0): normal map etkisinin gücü. 0 = düz yüzey, 1 = normal, 2 = abartılı.
- **roughness_multiplier** (0-2, default 1.0): roughness'ı çarpan. 0 = ayna gibi, 2 = aşırı mat.
- **ao_strength** (0-1, default 1.0): AO'nun ne kadar uygulansın. 0 = AO yok, 1 = full.

## V21 breaking changes

### Slope rock auto-blend kaldırıldı

V19'dan beri var olan "yüksek eğimde slot 2 otomatik rock olarak triplanar mapping" özelliği **kaldırıldı**. Sebepler:
- Sadece slot 2'yi özel davranışa zorluyordu
- Yeni 4-slot PBR sisteminde tutarsız
- Kullanıcı zaten brush ile eğim-tabanlı boyama yapabiliyor

Backward compat: `slope_rock_factor` @export'u korundu, setter no-op. Eski sahnelerde scene save sırasında bu property hâlâ var ama hiçbir yere bağlı değil.

**Rock istiyorsan:** slot 2'ye rock albedo+normal+rough+ao koy, brush ile yüksek eğimli yerlere boya.

### Shader uniform paketi değişti

`tex_a_0..3` aynı ama yeni uniform'lar (`tex_n_*`, `tex_r_*`, `tex_ao_*`) eklendi. Eski shader'la oluşturulmuş material'lar (zaten otomatik regenerate ediliyor) yenisi ile uyumsuz değil — `_setup_default_shader` material'ı yeniden inşa ediyor.

Eğer **özel material kullanıyorsan** (terrain_material'ı manuel set ettiysen), uniform'ları manuel update etmen gerekebilir.

## Migration (eski sahneleri açma)

V19/V20 sahnelerini V21'de açtığında:
1. `_ready()` PBR array'lerini auto-pad ediyor (`terrain_normal`, `terrain_roughness`, `terrain_ao` boş başlıyor, `terrain_textures` boyutunda doluyor null'larla)
2. Shader otomatik yeniden inşa ediliyor
3. Görüntü değişiyor: önce çıplak albedo görüyorduğun yerler, şimdi flat normal + full roughness + no AO ile (yine düz görünür ama bug değil)
4. Asset Manager'ı aç, her slot için 🔍 Tespit'e bas — kardeş map'leri varsa otomatik dolacak

Eğer kardeş map yoksa, manuel olarak Inspector'da Albedo'nun yanındaki Normal/Roughness/AO picker'larına sürükleyebilirsin.

## Beyazımsı görünüm sorunu (V20.1'de)

V20.1 screenshot'ında terrain çok pale/beyaz görünüyordu. Sebep V21'in çözdüğü tam aynı şey: **PBR maps eksikti**. Sadece düz albedo → ışıklandırma sığ → flat görünüm.

V21 ile aynı texture seti normal+rough+AO ile beraber bağlandığında:
- Normal map sürtünme detayını gösterir
- Roughness farkından kontrast oluşur
- AO kenarlara doğal gölge verir
→ derin, gerçekçi terrain.

## Test sırası

1. ZIP'i kur, plugin disable+enable
2. **Mevcut MobileTerrain3D node'unu seç**
3. Asset Manager butonuna bas (UI'de "Varlıkları Yönet")
4. Slot 0 zaten doluysa (forrest_ground_01_diff_1k) → 🔍 Tespit'e bas
5. Output panel'inde:
   ```
   [MobileTerrain3D] Slot 0 için otomatik tespit:
     ✓ Normal: res://forrest_ground_01_nor_gl_1k.png
     ✓ Roughness: res://forrest_ground_01_rough_1k.png
     ✓ AO: res://forrest_ground_01_ao_1k.png
   ```
6. Viewport'ta terrain artık detaylı, kontrastlı, gerçekçi olmalı

Ayrıca **Inspector'da yeni PBR map'lerin import ayarlarını kontrol et**:
- Normal map: `Compress → Normal Map → Enabled` olmalı (V20.1 fix scripti bunları yanlışlıkla disable etmiş olabilir; `_nor_gl` marker'ı içerdiği için bu durumda OK ama emin ol)
- Roughness/AO: Normal Map → Disabled

---

# MobileTerrain3D V20.1 — Hotfix

V20'da gerçek Godot 4.6.2 mobile renderer'da iki regresyon yaptım. Tespit edildi (kullanıcı screenshot ile), bu sürümde geri sarıldı.

## V20.1 hotfix detayları

### 🔴 Regresyon S1-revised: `MODEL_NORMAL_MATRIX` Mobile renderer'da shader'ı sessizce bozuyor

**Semptom:** Terrain tamamen siyah/transparan render edildi — sadece editor floor grid'i ve brush decal cursor görünüyor. Texture slot dolu olsa bile.

**Sebep:** V20'de S1 fix'i `(MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz` → `MODEL_NORMAL_MATRIX * NORMAL` değişimini yaptı. `MODEL_NORMAL_MATRIX` Godot 4.0+'da Forward+ renderer'da çalışıyor ama Mobile renderer'da silently compile fail oluyor — error log da net değil. Sonuç: fragment shader hiç çalışmıyor, terrain invisible.

**Düzeltme:** `mat3(MODEL_MATRIX) * NORMAL` formuna geri döndüm. Bu orijinal kodla matematiksel olarak aynı (sadece syntax daha temiz). Non-uniform scale altında normaller çarpık (eski S1 bug'ı geri geldi) ama **terrain görünür**. Trade-off: kullanıcılar terrain'i non-uniform scale ile transform etmemeli (terrain editör'ünde nadiren yapılan bir şey).

### 🔴 Regresyon U3-revised: `set_shader_parameter(..., null)` Mobile'da silent fail

**Semptom:** S1 ile birlikte muhtemelen terrain bozulmasına katkıda bulunmuştur. İzole olarak tespit edilmedi ama defansif fix uyguladım.

**Sebep:** V20 U3 fix'i empty slot uniform'larını `null` ile set etmeye çalışıyordu. Godot 4'te `set_shader_parameter` ile tip uyuşmazsa **silently keeps old value** — yani `null` sampler2D için yanlış tip, çağrı no-op olur. Eski uniform stale kalır. Orijinal U3 bug'ı çözülmedi.

Ayrıca bazı Mobile renderer konfigürasyonlarında null set'leri başka shader durumlarını da etkiliyor olabilir.

**Düzeltme:** Yeni helper `_get_or_create_blank_texture()` ekledim. 1x1 transparent RGBA ImageTexture, lazy-init, singleton. Boş slot'lar bu blank texture'a set edilir. Tip uyumlu (Texture2D), Godot kabul ediyor, uniform doğru şekilde rebind ediliyor.

## V20.1'de bilinen non-bug ama dikkat edilmesi gereken

**`forrest_ground_01_diff_1k` ETC2_RG11 olarak import edilmiş**

Screenshot'taki inspector "1024×1024 ETC2_RG11" gösteriyor. **ETC2_RG11 normal map formatıdır (sadece R+G kanalları)**. Diffuse texture için yanlış — mavi kanalı kaybediyorsunuz, kahverengi/yeşil renkler bozulur.

Bu addon'un bug'ı değil, **Godot'un import preset bug'ı/yanlış seçimi**. Düzeltmek için:

1. FileSystem'de `forrest_ground_01_diff_1k.webp` üzerine tıkla
2. Sağda **Import** tabına geç (Scene tabının yanı)
3. **Compress** kategorisinde **Mode** dropdown'undan **VRAM Compressed** veya **Lossless** seç
4. **Compress → High Quality** veya **Lossless** kullan
5. **Reimport** butonuna bas

Önerilen ayarlar mobile için:
- **Mode:** VRAM Compressed
- **High Quality:** off (mobile için size'ı küçük tutar)
- **Normal Map:** Disabled (bu önemli! disable etmezsen Godot ETC2_RG11 zorlar)

Bu ayarlar mobile uyumlu RGBA8 sıkıştırma kullanır, tüm 4 kanal korunur.

---

# MobileTerrain3D V20 — Original Bug Fix Release

Bakım sürümü. 25 bug fix, hiçbir yeni feature yok. Tüm değişiklikler kod içinde `V20 FIX` etiketleriyle yorum eklenmiştir; bir bug'a neden ve nasıl yaklaşıldığını anlamak için ilgili fonksiyonun başındaki block yorumları okuyun.

Kategoriler ve önem:
- 🔴 **Kritik**: Silent data corruption, crash, ya da çalışmayan core feature
- 🟠 **Orta**: Görünür bug, performans veya UX sorunu
- 🟢 **Minor/latent**: Edge case, defansif düzeltme, ya da V20 fix'lerin yan etkisi

## 🔴 Kritik fix'ler (6)

### Bug #1 — Brush cursor decal görünmüyordu
**Dosya:** `mobile_terrain_plugin.gd` (`_create_brush_cursor`, `_attach_brush_cursor_to`, `_detach_brush_cursor`)

Decal eski versiyonda `get_editor_main_screen()` (Control) altına parent ediliyordu. Control'ün World3D'si yok → decal silently render edilmiyordu. Yeni kod decal'i unparented oluşturuyor, `_edit()` çağrısında selected terrain'e (Node3D, World3D'si var) `top_level=true` ile attach ediyor, `INTERNAL_MODE_BACK` ile Scene dock'tan gizliyor, owner verilmeden saved scene'e sızdırmıyor.

### Bug #2 — `force_update_all()` undefined
**Dosya:** `mobile_terrain_node.gd` (yeni method)

EditorUndoRedoManager undo aksiyonları `add_do_method`/`add_undo_method` ile fonksiyonu **string ile** çağırıyor. `force_update_all` method'u tanımlı değildi → undo çalıştığında sessizce no-op. Yeni implementasyon tüm chunk'ları yeniden mesh'liyor, `dirty_chunks` temizliyor.

### Bug #3 — Splatmap undo GPU texture'ı sync etmiyordu
**Dosya:** `mobile_terrain_node.gd` (yeni `force_refresh_splatmap`), `mobile_terrain_plugin.gd` (paint mouse-up branch)

Splatmap undo eski kodda sadece byte array'i restore ediyordu, GPU texture eski painted state'inde kalıyordu. Yeni `force_refresh_splatmap` byte array'den GPU texture'ı yeniden inşa ediyor. Paint undo aksiyonuna `add_do_method`/`add_undo_method` ile `force_refresh_splatmap` çağrısı eklendi.

### Bug #4 — Object placement için undo yok
**Dosya:** `mobile_terrain_node.gd` (signal `foliage_placed`), `mobile_terrain_plugin.gd` (`_on_foliage_placed`, `_commit_placement_undo`)

Object placement (tool 8) hiçbir undo entry yaratmıyordu. Sculpt undo branch'i yanlışlıkla bu tool için tetikleniyordu (heightmap_backup duplicate eden tip). Yeni signal-based architecture: node `foliage_placed` emit ediyor, plugin her placement'ı kayıt ediyor, mouse-up'ta `set_instance_transform` + `instance_count` deltası ile undo action build ediyor.

### Bug #5 — `map_size` değişiminde splatmap resize edilmiyordu
**Dosya:** `mobile_terrain_node.gd` (`_initialize_splatmap` tamamen yeniden yazıldı, `_set_map_size`)

map_size 256 → 128 olunca splatmap_texture_local hala 256x256 kalıyordu. Yeni paint çağrıları boundary'lerde crash veya silent fail. Yeni implementasyon dört durumu açıkça handle ediyor: texture var + boyut uyuyor (sync), texture var + boyut uyuşmuyor (bilinear resize), texture yok + data geçerli (rebuild), texture yok + data geçersiz (default doldur).

### Bug #6 — Splatmap normalize matematiği yanlıştı (slot temizlenemiyor)
**Dosya:** `mobile_terrain_node.gd` (`_paint_splatmap`)

Eski algoritma: tek kanala lerp, sonra sum normalize. Sonuç: diğer slotlar asla 0'a inmiyor — slot 0'ı tam basınca (0, 1, 0, 0) üzerine en fazla (0.33, 0.67, 0, 0) yapabiliyordun. Slot temizleme imkansızdı. Yeni "competitive blending": tüm kanalları `(1 - bf)` ile çarp, hedef kanala `bf` ekle. Matematiksel olarak: eğer eski toplam=1 ise yeni toplam=1, otomatik normalize. Slot 0'ı tam basınca (1, 0, 0, 0) çıkar.

## 🟠 Orta önem fix'leri (11)

### Bug #7 — Erosion sadece source chunk'ı dirty mark ediyordu
**Dosya:** `mobile_terrain_node.gd` (`_erode_height`)

Erozyon material'i chunk sınırlarından geçirdiğinde destination chunk'ın mesh'i güncellenmiyordu. Visible vertical step her 32 cell'de. Hem source hem destination chunk şimdi dirty mark ediliyor. Ayrıca dirty mark `if lowest_idx != -1` bloğunun içine taşındı — düz alanlarda gereksiz re-mesh önlenmiş oldu.

### Bug #8 — `int()` negative coord truncation
**Dosya:** `mobile_terrain_node.gd` (`get_intersection_raymarch_persistent`)

`int(x)` zero'ya doğru truncate yapıyor: `int(-0.3) == 0`. Terrain edge'inin batı/güneyinde rare spurious hit'lere yol açıyordu. `floori()` (floor-as-int) ile değiştirildi: `floori(-0.3) == -1` ve bound check doğru reject ediyor.

### Bug #9 — Raymarch step çok kabaydı
**Dosya:** `mobile_terrain_node.gd` (`get_intersection_raymarch_persistent`)

Eski step `dir * 2.0` her iteration'da iki cell atlatıyordu, ince ridge ve peak'leri tamamen atlıyordu. 1-unit step'e indirildi (heights per-vertex stored, en küçük anlamlı step = 1). Iter sayısı 500'de kaldı → max travel 500 birim (eski 1000 birim nadiren tükeniyordu çünkü `y < global_position.y - 100` early termination var).

### Bug #10 — False positive (foliage Basis math)
Re-analyze sonucu: kod doğru. Random yaw orientation'ı zaten scramble ediyor, hipotetik forward direction bug'ı gözle görülmüyor. Fix uygulanmadı.

### Bug #11 — `_on_object_changed` multimesh leak
**Dosya:** `mobile_terrain_node.gd` (yeni `repurpose_multimesh_to`), `mobile_terrain_plugin.gd` (`_on_object_changed` yeniden yazıldı)

Slot'un mesh'ini değiştirince eski mesh için olan MultiMesh orphan kalıyordu, 50 placement'lı bir tree multimesh sahnede UI'sız render etmeye devam ediyordu. Üç-aşamalı fix: (1) `repurpose_multimesh_to` ile eski multimesh'i yeni mesh'e re-key — kullanıcının placement'ları korunuyor; (2) `_get_or_create_multimesh` fallback; (3) her durumda `garbage_collect_multimeshes` ile orphan temizliği.

### Bug #12 — `map_size % chunk_size ≠ 0` durumda uncovered hücreler
**Dosya:** `mobile_terrain_node.gd` (`_align_to_chunks` helper, `_set_map_size`, `_set_chunk_size`)

`num_chunks = map_size / chunk_size` integer division yapıyordu. map_size=100, chunk_size=32 ise sadece 96 hücre kaplanıyordu, cells 96-99 hiç render edilmiyor ve paint edilemiyor. Auto-round + `push_warning` ile setter'lar artık map_size'i chunk_size'ın katına yuvarlıyor. Negative chunk_size guard'ı (`val < 1: val = 1`) eklendi.

### Bug #13 — Last chunk'ın outer vertex'i clamp → flat edge strip
**Dosya:** `mobile_terrain_node.gd` (`update_chunk_mesh`)

8 chunks × 33 vertices = 257 unique vertex gerekiyordu ama height_data 256² = 256 vertex'lik. Last vertex sample `clampi(256, 0, 255)` ile 255'e düşüyordu → terrain'in doğu/güney edge'inde 1 hücre genişliğinde **görünür düz strip**. Last chunk'ın vertex sayısı `chunk_size+1` yerine `chunk_size` olarak clip edildi. Effective terrain genişliği 256→255 (%0.4 fark, pratikte görünmez). Chunk seam'leri watertight kalıyor.

### Bug #14 — Brush dab başına 256KB splatmap copy
**Dosya:** `mobile_terrain_node.gd` (`_splatmap_stroke_image` cache, `start_stroke`, `end_stroke`, `_paint_splatmap`)

Her dab'da `splatmap_texture_local.get_image()` full 256KB CPU copy yapıyordu. 60Hz brush'ta ~46 MB/s throwaway allocation. Stroke başında image cache, dab'lar in-place modify, stroke sonunda byte array sync. Stroke içinde redundant shader rebind ve byte sync skip edildi. Tipik 1 saniye paint stroke: 30 MB allocation → 256 KB allocation.

### Bug #15 — Mouse-down'da eager heightmap 256KB duplicate
**Dosya:** `mobile_terrain_plugin.gd` (`_ensure_backup_for_current_tool` helper)

Her mouse-down'da terrain dışı tıklama bile 256KB heightmap_backup veya splatmap_backup copy'si yapıyordu. Useless undo entry de yaratıyordu. Lazy snapshot: backup'lar ilk gerçek brush call'dan önce alınıyor, hiç brush call yoksa hiç copy yapılmıyor ve undo entry de oluşmuyor. Yan etki: terrain dışı tıklama mouse-up'lar artık undo history'ye no-op girmiyor.

## 🟢 Minor / latent / V20 yan etki fix'leri (8)

### Bonus #1 — Brush bounds off-by-one
**Dosya:** `mobile_terrain_node.gd` (7 brush fonksiyonu × 2 axis = 14 yer)

`max_x = min(map_size-1, ...)` ve `range(min_x, max_x)` exclusive end nedeniyle son satır/sütun (`map_size-1`) hiç paint/sculpt edilemiyor. `min(map_size, ...)` ile düzeltildi. İlginç tutarsızlık: _erode_height'ın inner neighbor loop'u zaten doğru pattern kullanıyordu (`min(map_size, z+2)`), yazar bir yerde doğru yapmış başka yerde unutmuş.

### Notice #1 — `initialize_terrain` veri korumalı migration
**Dosya:** `mobile_terrain_node.gd` (`initialize_terrain`)

V20 #12 fix'in (auto-round map_size) yan etkisi: eski sahneler `map_size=100, chunk_size=32` ile açıldığında auto-round map_size'i 96 yapıyor, ardından `initialize_terrain` size mismatch görüp `height_data.resize() + fill(0.0)` ile tüm kullanıcı çalışmasını siliyordu. Fix: data'nın square layout olduğu doğrulanırsa cell-by-cell migration (top-left corner preservation), aksi durumda eski davranış (sıfırla). map_size manuel değişikliklerinde de (256→128 vb.) artık veri korunuyor.

### Notice #2 — `last_placement_pos` stroke'lar arası sızıyordu
**Dosya:** `mobile_terrain_node.gd` (`start_stroke`)

`last_sculpt_pos` start_stroke'ta `Vector3.INF`'e reset ediliyordu ama `last_placement_pos` reset edilmiyordu. Object placement tool'da: stroke 1'in son object'inin pozisyonu stroke 2'ye sızıyordu, kullanıcı yeni stroke ile yakın bir yere tıklarsa "3.0 unit min spacing" check'i fail oluyor, **sessizce object yerleştirilmiyordu**. start_stroke şimdi ikisini de reset ediyor.

### Shader #S1 — Normal MODEL_MATRIX ile dönüştürülüyordu
**Dosya:** `mobile_terrain_node.gd` (`TERRAIN_SHADER` vertex shader)

Normaller `MODEL_MATRIX` ile dönüştürülemez — inverse transpose lazım. Godot 4'ün built-in'i `MODEL_NORMAL_MATRIX`. Non-uniform scale (1, 2, 1) terrain'de slope hesabı çarpık, auto-rock effect yanlış yerlere çıkıyordu.

### Shader #S2 — Interpolated normal fragment'ta re-normalize edilmiyordu
**Dosya:** `mobile_terrain_node.gd` (`TERRAIN_SHADER` fragment shader)

Varying interpolation unit length'i korumuyor. `slope = 1 - v_world_normal.y` direkt kullanılınca ~%50 hata olabiliyordu (corner normals (0,1,0) ve (0.707,0.707,0) midpoint length 0.924). Fragment'ta `vec3 N = normalize(v_world_normal);` ile düzeltildi. slope_rock_factor decision'ları artık doğru.

### Shader #S3 — Triplanar normalization NaN riski
**Dosya:** `mobile_terrain_node.gd` (`TERRAIN_SHADER` fragment shader)

Degenerate triangle (N == vec3(0)) durumunda `triplanar_normal /= 0` NaN üretiyordu. Epsilon clamp eklendi: `max(sum, 0.0001)`. Defansif, gerçekçi triangles için no-op.

### Brush #B1 — `_smooth_height` order-dependent in-place
**Dosya:** `mobile_terrain_node.gd` (`_smooth_height`)

`height_data`'dan okuyup `height_data`'ya yazıyordu. Scan order'da (x-1, z-1) zaten smoothed olduğu için sonraki cell'ler stale değil smoothed neighbor okuyor → **upper-left'ten lower-right'a asimetrik smearing**. Erosion zaten doğru pattern'i kullanıyordu (temp buffer); aynı pattern smooth'a da uygulandı. PackedFloat32Array COW sayesinde maliyet 256KB per dab.

### UI #U1 — Dropdown selection desync
**Dosya:** `mobile_terrain_plugin.gd` (`_update_dropdowns`)

`clear()` + repopulate yapıyordu ama selection restore etmiyordu. Kullanıcı slot 2'yi seçtikten sonra bir texture değiştirse, dropdown görsel olarak slot 0'a snap atıyor ama `current_paint_slot` hala 2'de kalıyor. **Görsel ≠ gerçek state — confused UX**. Fix: clamp selection to new bounds + `.select()` + node'a sync-back.

### UI #U2 — Sharp brush cursor square render
**Dosya:** `mobile_terrain_plugin.gd` (`_generate_decal_texture`)

`if norm <= 1.0: alpha = 1.0` koşulu — `norm = clampf(dist/max_r, 0, 1)` ile zaten daima ≤1.0 → tüm 128×128 pixel alpha=1 → square cursor. Gerçek brush davranışı round. `if dist <= max_r` (raw distance) ile düzeltildi, cursor şimdi gerçek brush footprint'ini gösteriyor.

### UI #U3 — Texture slot remove → shader uniform stale
**Dosya:** `mobile_terrain_node.gd` (`update_shader_textures`), `mobile_terrain_plugin.gd` (`_remove_texture_slot`)

`update_shader_textures` `if size > i:` koşullarıyla doluyordu — array shrink olunca remove edilmiş slot'ın uniform'u stale kalıyordu, splatmap channel hala eski texture'ı render ediyordu. Fix: her zaman 4 slot'u explicit yaz (null kullanıcı boş slot için, hint_default_black fallback'i tetikler). `_remove_texture_slot` artık `update_shader_textures` çağrısı yapıyor.

### Bug #M1 — `_mark_chunk_dirty` asimetrik propagation
**Dosya:** `mobile_terrain_node.gd` (`_mark_chunk_dirty`)

Cross-chunk normal dependency'leri için 3 koşul vardı ama 4.'sü eksikti: vertex chunk N'de local x=1 olduğunda chunk N-1'in son vertex'inin normal'ini etkiliyor (`hR = get_height((N+1)*chunk_size + 1)`). Etki: chunk seam'lerinde **view-angle-dependent lighting şeritleri**. Symetrik koşul eklendi.

### Bug #E1 — `_import_exr` shared image reference
**Dosya:** `mobile_terrain_node.gd` (`_import_exr`)

`ImageTexture.get_image()` Godot 4'te shared reference döner. Sonraki `decompress()` ve `resize()` çağrıları yerinde modifiye eder → import_texture'ın iç state'i bozulur. `CompressedTexture2D` için fresh image döner (güvenli), `ImageTexture` için değil. Defansif `duplicate()` eklendi.

## Test edilmemiş — gerçek Godot 4'te doğrulama gerekli

Hiçbir fix canlı çalıştırılmadı, sadece kod review + mantık yürütme. Test edilmesi gereken senaryolar:

**🔴 Yüksek öncelik:**
- Her brush tool'u ile sculpt, sonra Ctrl+Z (#2, #3, #4 fix'leri)
- Splatmap painting: slot 0 → slot 1 → tekrar slot 0 (slot temizleme #6)
- map_size değiştirme: 256 → 128 → 256 (data preservation #5 + Notice #1)
- Object placement undo: 5 obje yerleştir, Ctrl+Z 5 kere (#4)
- Chunk seam visual check: terrain'i farklı açılardan incele, lighting şerit yok mu (#13, #M1)
- EXR/PNG heightmap import (#E1)

**🟠 Orta:**
- Brush cursor görünüyor mu, terrain'in altında kalmıyor mu (#1)
- Erosion brush'tan sonra mesh boundary'lerinde step yok mu (#7)
- Slot remove sonrası eski texture render etmiyor mu (#U3)
- Object slot mesh değiştir → eski placements görünmüyor mu (#11)

**🟢 Edge:**
- map_size=100 (non-divisible) sahne aç → warning + data preservation (#12, Notice #1)
- Non-uniform scaled terrain'de slope-based rocks doğru yerlerde mi (#S1)
- Dropdown'da slot seçtikten sonra texture değiştir → selection korunuyor mu (#U1)

## Kümülatif değişiklik istatistikleri

- **node.gd**: 636 satır → 1231 satır (+93%)
- **plugin.gd**: 497 satır → 790 satır (+59%)
- **Toplam**: 1133 → 2021 satır (+78%)
- Eklenen kod büyük çoğunluğu yorum (V20 FIX block'ları): "neden" ve "nasıl"ı kapsayan trace edilebilir maintenance documentation
