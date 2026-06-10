# TKT-010 — Tam Eklenti Denetim Raporu

Tarih: 2026-06-10 · Godot 4.6.2.stable (gerçek binary ile doğrulandı)
Test kanıtı: `test/run_all.sh` → **15/15 ALL TESTS PASSED** — yani bütün bulgular
test edilmeyen dikişlerde yaşıyor; pipeline yeşilken eklenti yine de kırık.

Denetim yöntemi: 3 paralel salt-okur denetçi (yerleştirme uçtan-uca, performans
sıcak yolları, editör kabuğu) + baş denetçinin elle doğrulaması. Aşağıdaki her
bulgu kod satırı kanıtıyla; S1/S2/P1 sınıfı bulgular ayrıca elle doğrulandı.

---

## A. EŞYA YERLEŞTİRME — baş şikayetin kök nedeni

### A1 — S1 (veri kaybı): Mesh-kimlik zinciri kopuyor
**Kanıt:** node.gd:54 (`@export asset_meshes` → .tscn'e gömülür),
node.gd:1049 + mobile_terrain_data.gd (`object_slots` mesh'i .res'e gömer),
node.gd:1681/1777 (iki farklı instance ile registry erişimi),
node.gd:1702 (`if mesh in asset_meshes` — kimlik karşılaştırması),
plugin.gd:1659/1705 (GC tetikleyicileri).

Path'siz mesh'lerde (BoxMesh/SphereMesh gibi inspector primitifleri) aynı mesh
hem `.tscn`'e hem `.res`'e AYRI kopya olarak gömülüyor. Sahne yeniden açılınca:
1. `.res`'ten dönen yerleştirmeler B kopyasıyla anahtarlanır; asset slot'ları A kopyasını taşır.
2. Yeni yerleştirme A'yı registry'de bulamaz → **ikinci bir `Assets_BoxMesh`** doğar; eski ve yeni nesneler ayrı batch'lere bölünür.
3. Herhangi bir slot değişikliği `garbage_collect_multimeshes()` çağırır → B, `asset_meshes`'te "yok" sayılır → **yüklenen tüm yerleştirmeler `queue_free` ile silinir.**
4. Her save/load döngüsü kopyaları katlar (A,B → A,B,C → ...).

Dosya yolundan yüklenen mesh'lerde (.glb/.obj) ResourceLoader cache kimliği
koruduğu için belirti yoktur — bu yüzden bug "bazen oluyor" gibi görünür.

**Repro:** BoxMesh slotu ekle → 10 nesne yerleştir → kaydet → sahneyi kapat/aç
→ 1 nesne daha yerleştir → iki `Assets_BoxMesh` çocuğu; slot değiştir → 10 eski
nesne yok olur.

**Test boşluğu:** `object_roundtrip.gd` aynı süreçte save/load yapar; reload
sonrası "tam olarak 1 Assets_* çocuğu var" assert'i hiçbir testte yok.

### A2 — S2: Boş "Terrain Place Objects" undo aksiyonu
undo_recorder.gd:70-91 — `create_action` koşulsuz, döngü tüm MMI'leri
atlayabilir (`is_instance_valid` / `after_count == initial`), `commit_action`
yine de çağrılır → undo geçmişine hayalet kayıt; her Ctrl+Z bir slot yakar.

### A3 — S3: `stride=0` → undo nesneleri orijine ışınlar
undo_recorder.gd:86-87 — `after_count == 0` iken `before_buffer` boş kesit;
undo `_apply_object_buffer(mm, initial, [])` → `initial` örnek origin'de klon.
Düzeltme yönü: TRANSFORM_3D için stride=12 fallback.

### A4 — S3: `_make_visible(false)` asimetrik temizlik
plugin.gd:2115 — `placement_records` temizleniyor, `placement_initial_counts`
temizlenmiyor (gelecek regresyonlara açık kapı).

### A5 — S3: `placement_records` ölü ağırlık
undo_recorder.gd:65-68 — parametre yalnız `is_empty()` için kullanılıyor; 500
yerleştirmelik sürüklemede 500 dictionary boşuna birikiyor; yanlış kapı
semantiği (kayıt yok ≠ yerleştirme yok).

### Temiz çıkanlar (yerleştirme)
Spacing reset'i, `should_place` INF sözleşmesi, double-connect koruması
(plugin.gd:2032), atomik `_apply_object_buffer` deseni, runtime'da restore
(oyun içinde nesneler görünür), path'li mesh roundtrip — hepsi doğru.

---

## B. PERFORMANS — "asla optimize değil" haklı çıktı

### P1 — donma seviyesi (5 adet)
| # | Yer | Sorun | Maliyet |
|---|---|---|---|
| B1 | sculpt_ops.gd:85,167 | smooth/erode HER dab'de tüm heightmap'i `duplicate()` ediyor ("COW ucuz" yorumu yanlış — duplicate her zaman tam kopya) | 1280² → dab başına 6.5 MB; 25 Hz'de **162 MB/s** bellek trafiği |
| B2 | node.gd:2089 | paint HER dab'de TÜM splatmap'i GPU'ya yüklüyor (`ImageTexture.update` tam upload) | 25 Hz'de **163 MB/s** GPU upload; mobilde bus doyumu |
| B3 | object_placement.gd:147-153 | `place_one` her yerleştirmede TÜM transform'ları RS üzerinden kopyalıyor → sürüklemede O(n²) | 8192 tavanında yerleştirme başına 16.384 RS çağrısı ≈ **~16 ms donma**. Düzeltme: `mm.buffer` oku/yaz (O(1)) |
| B4 | plugin.gd:2231-2361 | fırça imleci HER MouseMotion'da 400 `get_height` + ~2.166 ImmediateMesh RS çağrısı | 60 Hz'de ~130K RS çağrısı/sn — sadece imleç için |
| B5 | node.gd:1549+1471 | undo `force_update_all` + 0.15s LOD taraması koordinasyonsuz; ikisi de `dirty_chunks`'ı basıyor → çifte tam-rebuild dalgası | 1024 chunk'ta undo ≈ 2.7+ sn meşgul editör |

### P2 — hissedilir takılma (başlıcaları)
- **B6** node.gd:1955,2082 — `BrushSystem.new` + mask LUT'u HER dab'de yeniden bake (512² mask = dab başına 262K iterasyon); tek instance cache'lenmeli
- **B7** splatmap_system.gd:61,77 — pixel başına `get_pixel/set_pixel` → ~392K GDScript→C geçişi/sn; PackedByteArray indekslemeye geçilmeli
- **B8** chunk_renderer.gd:69-142 — chunk başına 6 taze packed-array (~76 KB) → 64 chunk/frame'de ~4.9 MB/frame alloc; buffer havuzu gerekli
- **B9** node.gd:1471-1478 — LOD taraması her 0.15s'te TÜM chunk'larda dict-lookup + `keys()` alloc; zoom'da kitlesel rebuild (histerezis yok)
- **B10** plugin.gd:1131-1257 — TEK texture değişiminde TÜM asset paneli (48+ kontrol) yıkılıp kuruluyor
- **B11** raymarch_system.gd:80-85 — 1 birim sabit adım, motion başına 2000+ iterasyon; kademeli adım/erken-çıkış yok
- **B12** plugin.gd:636-642 — fırça mask popup'ı her açılışta diski tarayıp 20 texture'ı yeniden yüklüyor

### P3 — israf (özet)
dirty-loop geçici Array'leri (node.gd:1250), dab başına lambda alloc
(node.gd:1956), hücre başına 4'e kadar dict yazımı (node.gd:2168), undo'da 6.5
MB Image alloc + boyut için `get_image()` (node.gd:1601-1626), `_axis_samples`
append-realloc (chunk_renderer.gd:157), coarse LOD'da ±1 cold-cache normal
okumaları (chunk_renderer.gd:92), her raycast'te `affine_inverse`
(raymarch_system.gd:51), toggle başına StyleBoxFlat (plugin.gd:1859).

---

## C. EDİTÖR KABUĞU — diğer doğruluk bulguları

| # | Sev | Yer | Sorun |
|---|---|---|---|
| C1 | S3 | plugin.gd:1355-1383 | Slot silmede 4 skaler PBR dizisi (`texture_scale`, `normal_strength`, `roughness_multiplier`, `ao_strength`) atlanıyor; `_sync_pbr_array_sizes` sondan buduyor → kalan slotların tiling/PBR değerleri KAYIYOR (elle doğrulandı) |
| C2 | S3 | plugin.gd:1880-1911 | `_exit_tree` aktif stroke'u finalize etmiyor → plugin kapatılırken açık undo aksiyonu askıda |
| C3 | S3 | plugin.gd:2153 | `_finalize_active_stroke` null'ı kontrol ediyor ama freed-object'i etmiyor → node silme + plugin kapama yarışında crash |
| C4 | S4 | plugin.gd:543-555 | Bağlanmamış ölü callback'ler; biri yanlış semantik (index ≠ item ID) — bakım tuzağı |
| C5 | S4 | plugin.gd:582,976,1988 + node.gd ~15 nokta | TerrainDiagnostics kataloğunu baypas eden çıplak push_warning/push_error |
| C6 | S4 | fix_texture_imports.gd:180 | `scan_sources()` import sürerken sessiz düşebilir; `is_importing()` kontrolü yok |
| C7 | S4 | test_input_router.gd:77-79 | Mock, gerçek koddaki null-guard'ı taşımıyor (mock/gerçek sapması) |

---

## Önerilen fix sırası (henüz uygulanmadı — sahip onayı bekliyor)

1. **A1** mesh-kimlik zinciri (S1, baş şikayet) + reload-kimlik regresyon testi
2. **B1-B5** beş P1 performans fix'i (her biri bağımsız, ayrı commit)
3. **A2-A5 + C1-C3** doğruluk paketi
4. P2'ler (B6-B12) — ayrı oturum
5. C5 tanı kataloğu temizliği + C4 ölü kod — birikimli

Her adım extract-system/quality-gate skill prosedürüne tabi: test önce kırmızı,
fix sonra `ALL TESTS PASSED`, performans fix'lerinde önce/sonra ölçüm notu.
