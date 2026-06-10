---
name: extract-system
description: Monolitik node.gd/plugin.gd içinden bir sistemi (chunk, heightmap, foliage, persistence, shader-binding, editor-UI paneli) güvenle systems/ veya editor/ altına çıkarır. Karakterizasyon testi önce yazılır, sahne uyumluluğu korunur, pipeline yeşil kalmadan iş bitmez. V22_STATUS.md'deki extraction tablosundan bir satır işlerken kullan.
version: 1.0.0
---

# extract-system — Güvenli Sistem Çıkarma Prosedürü

## Amaç ve kapsam
`mobile_terrain_node.gd` (~2184 satır) ve `mobile_terrain_plugin.gd` (~2367 satır)
içindeki monolitik sistemleri `addons/mobile_terrain/systems/` ve `editor/` altına
taşımak. Hedef listesi `V22_STATUS.md` "Hâlâ monolitik kalan kısımlar" tablosudur.
**Tek seferde tek sistem.** Bir oturumda en fazla 2-3 sistem (V22_STATUS bütçesi).

## Standart izlenebilirlik matrisi
| Adım | Standart (docs/STANDARDS.md) | Madde |
|---|---|---|
| 2: Zachman hücreleri | Zachman Framework | 1.2 |
| 3: karakterizasyon testi önce | ISO/IEC/IEEE 29119 | 1.7 |
| 4-5: delegasyon shim + @export koruması | SemVer (MAJOR sabit) | 2.1 |
| 6: pipeline yeşil | ISO 9001 PDCA "Check" | 1.10 |
| 7: STATUS/CHANGES güncelle | ISO 12207 yaşam döngüsü kaydı | 1.3 |
| Performans kuralları | ISO/IEC 25010 öncelik sırası | 1.6 |

## Ön koşullar
- `git status` temiz (kirli ağaç üstünde extraction başlatma).
- `bash test/parse_check.sh` yeşil (baseline kanıtı). Kirliyse önce onu düzelt.
- `V22_STATUS.md` tablosundan hedef satırı seç; satır aralıklarını **tabloya değil
  koda güvenerek** doğrula: `grep -n` ile fonksiyonların gerçek konumunu bul
  (tablo eski oturumdan kalmadır, satırlar kaymış olabilir).

## Prosedür

### 1. Sınırı çiz
Çıkarılacak fonksiyon kümesini listele. Her fonksiyon için sınıflandır:
- **Pure** (yalnız parametre okur, değer döner) → static metodlu sistem dosyası.
  Örnek desen: `systems/raymarch_system.gd`, `systems/sculpt_ops.gd`.
- **Stateful** (node üyelerine yazar) → sistem dosyası state'i parametre alır,
  node ince delegasyon shim'i tutar. Örnek: `systems/splatmap_system.gd` +
  `node.gd`'de kalan setter cascade.
- **Editor-bağımlı** (`EditorInterface`, `UndoRedo`) → `editor/` altına.
  Örnek: `editor/save_orchestrator.gd`, `editor/undo_recorder.gd`.

### 2. Zachman mini-hücrelerini dosya başına yaz
Yeni sistem dosyasının başına 4 satırlık yorum: **Ne** (hangi veri),
**Nasıl** (algoritma özeti), **Kim** (çağıranlar: node mu plugin mi),
**Neden** (extraction gerekçesi + V22_STATUS satırı).

### 3. Karakterizasyon testini ÖNCE yaz
`test/unit/test_<sistem>.gd` — mevcut davranışı yakalayan test, extraction'dan
ÖNCE mevcut kod yoluyla yeşil olmalı. Desen: mevcut `test_sculpt_ops.gd`,
`test_splatmap_system.gd`. Kurallar:
- Çıktı son satırı `<SISTEM>_TEST_OK` (run_all.sh grep sözleşmesi).
- `SceneTree`'siz `MainLoop`/`SceneTree` script olarak headless çalışır.
- Sınır değerleri test et: map_size kenarı, slot [0..3], boş veri.
- Test, `test/run_all.sh`'a yeni adım olarak eklenir (adım sayacını güncelle).

### 4. Sistemi çıkar
- Yeni dosya `@tool` ile başlar (editor'da yüklenir), `class_name` alır.
- Kod taşı, node/plugin'de **delegasyon shim** bırak: public API imzası DEĞİŞMEZ
  (`class_name MobileTerrain3D` ve tüm `@export`'lar korunur — mevcut .tscn
  sahneler kırılmaz; bu SemVer MAJOR sözleşmesidir).
- `.uid` dosyalarını Godot üretir; elle yazma, import adımına bırak.

### 5. Bilinen tuzaklar (geçmiş bug'lardan — HANDOFF.md ve CHANGES.md kanıtlı)
- **Image paylaşılan referans:** `img.get_data()` sonucunu sakladığın her yerde
  `.duplicate()` (node.gd:2210 vakası).
- **Image lock artığı:** `lock()/unlock()` çifti exception yolunda da kapanmalı
  (audit-general-image-lock-leftovers ajanının konusu).
- **`_get_property_list` + aynı isimde plain var = double-listing** (Godot
  #87636) — property eklemek gerekiyorsa `@export` + `_validate_property` da
  yetmez (HANDOFF Yaklaşım 1-2 başarısızlığı); persistence işine giriyorsan
  `editor/save_orchestrator.gd` Plan B desenine uy, `EditorInterface.save_scene()`
  re-entry'sine ASLA güvenme.
- **Deferred çağrıda bayat yakalama:** `call_deferred` ile taşıdığın lambda,
  capture ettiği node referansını `is_instance_valid` ile doğrulamalı.
- **Performans (ISO 25010 önceliği):** chunk/stroke sıcak yolunda yeni
  per-frame allocation YASAK; bütçeler `TerrainConstants` üzerinden okunur
  (`SYNC_BUILD_CHUNK_LIMIT=64`, `MAX_CHUNK_REBUILD_USEC=8000`), sabit gömme.

### 6. Doğrula
```bash
bash test/parse_check.sh        # parse temiz
bash test/run_all.sh            # TÜM suite + yeni test; son satır: ALL TESTS PASSED
```
Yeşil değilse extraction'ı küçült, ikiye böl; testi gevşetme.

### 7. Kayıt ve commit
- `V22_STATUS.md` tablosundan satırı düş, "tamamlananlar"a ekle.
- `CHANGES.md`'ye Keep-a-Changelog girdisi.
- Conventional commit: `refactor(systems): extract <sistem> from node.gd (TKT-XXX)`.

## Kabul kriterleri
- [ ] `test/run_all.sh` son satırı `ALL TESTS PASSED`
- [ ] `wc -l` ile node.gd/plugin.gd satır sayısı AZALDI (shim taşınan koddan küçük)
- [ ] `git diff` içinde hiçbir `@export` silinmedi/yeniden adlandırılmadı
- [ ] Yeni sistem dosyasında Zachman başlık yorumu var
- [ ] V22_STATUS.md + CHANGES.md güncellendi

## Hata yolları
- Parse hatası `class_name` çakışması veriyorsa: fixture'larda eski symlink
  kalmış olabilir → `test/fixtures/*/addons` symlink'lerini sil, script yeniden kurar.
- run_all'da yalnız YENİ test kırmızıysa: karakterizasyon testi extraction
  öncesi davranışı yanlış yakalamış demektir; testi koddan türet, kodu testten değil.
- Editor-runtime ayrımı sızıyorsa (`EditorInterface` systems/ altına girdiyse):
  geri al; systems/ dosyaları headless testte yüklenebilir KALMALIDIR.

## Changelog
- 1.0.0 (2026-06-10): İlk sürüm. V22_STATUS extraction tablosu + HANDOFF tuzak
  envanteri + mevcut test desenlerinden derlendi.
