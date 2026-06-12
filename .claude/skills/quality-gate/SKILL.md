---
name: quality-gate
description: Her merge/release öncesi zorunlu kalite kapısı — test pipeline'ı çalıştırır, log kanıtlarını yorumlar, ISO 25010 mobil performans bütçesini denetler ve CI kurulumunu yönetir. "Testleri çalıştır", "merge edilebilir mi", "kalite kontrolü" istendiğinde kullan.
version: 1.0.0
---

# quality-gate — Kalite Kapısı

## Amaç ve kapsam
Bir değişikliğin merge/release edilebilirliğine **kanıtla** karar vermek.
Kanıt = headless test logları + performans bütçe denetimi. "Bence çalışıyor" kabul değildir.

## Standart izlenebilirlik matrisi
| Adım | Standart | Madde |
|---|---|---|
| 1: pipeline çalıştırma | ISO/IEC/IEEE 29119 | 1.7 |
| 2: log kanıt yorumu | ISO 9001 (kanıta dayalı karar) | 1.10 |
| 3: performans bütçesi | ISO/IEC 25010 (performans > güvenilirlik > bakım) | 1.6 |
| 4: güvenlik grep'leri | OWASP ASVS / NIST SSDF | 2.3, 2.4 |
| 5: CI kurulumu | OpenSSF Scorecard | 2.7 |

## Ön koşullar
- `godot` binary'si PATH'te (`/usr/local/bin/godot`, 4.6.2 headless). Yoksa
  pipeline koşamaz — bunu açıkça raporla, "test edilemedi"yi "geçti" gibi sunma.

## Prosedür

### 1. Tam pipeline
```bash
bash test/run_all.sh
```
15 adım: parse check → 4 integration (save_roundtrip, multi_terrain, object_roundtrip,
scene_no_embed) → 11+ unit. Başarı sözleşmesi: her adımın logunda `*_OK` satırı,
son satır `ALL TESTS PASSED`. `set -euo pipefail` olduğundan ilk kırmızıda durur.

### 2. Kırmızıda log adli analizi
Loglar `/tmp/*.log` altında kalır (save_roundtrip.log, sculpt_ops.log, ...).
- `grep -i "SCRIPT ERROR\|Parse Error" /tmp/<adım>.log` → hangi dosya:satır.
- Kırmızı adım hangi sistemi test ediyorsa, suçlu o sistemin SON değişikliğidir;
  `git log --oneline -5 -- <ilgili dosya>` ile daralt.
- Integration kırmızı + unit yeşilse: sistemler arası sözleşme bozulmuş demektir
  (tipik: save akışında external_data_path / TERRAIN_DATA_DIR varsayımı).

### 3. Performans bütçe denetimi (mobil hedef — pazarlıksız)
Diff'te şu desenler varsa otomatik RED, gerekçesiyle geri gönder:
- Chunk rebuild / stroke sıcak yolunda (`_process`, `update_chunk_mesh`,
  `apply_dab` çağrı zinciri) yeni `Array`/`Dictionary`/`Image` allocation.
- `TerrainConstants` yerine gömülü sabit (bütçeler tek yerden yönetilir:
  `SYNC_BUILD_CHUNK_LIMIT=64`, `MAX_CHUNK_PER_FRAME=64`, `MAX_CHUNK_REBUILD_USEC=8000`).
- Stroke throttle atlaması: dab uygulaması `MIN_STATIONARY_INTERVAL` (0.04s)
  kontrolünü baypas edemez.
- Senkron full-rebuild: `SYNC_REBUILD_CHUNK_LIMIT` (256) üstünde chunk'ı tek
  frame'de yeniden kuran kod.
Denetim komutu örneği:
```bash
git diff main... -- addons/ | grep -nE '^\+.*(Image\.create|\.new\(\)|\[\]|\{\})' 
```
çıkanları sıcak yolda mı diye elle değerlendir (mekanik grep tek başına karar değildir).

### 4. Güvenlik mini-taraması
```bash
grep -rnE 'OS\.execute|HTTPRequest|FileAccess\.open\("/' addons/mobile_terrain/
```
Eklenti ağ erişimi, süreç çalıştırma ve mutlak yol YAZAMAZ (yalnız `res://`,
`user://`). İhlal = MT path-safety regresyonu; `test/unit/test_path_safety.gd`
(TKT-002 C1) genişletilerek kilitlenir.

### 5. CI kurulumu (henüz kuruluysa atla)
`.github/workflows/` yoksa şablonu kur: bu skill'in yanındaki `assets/ci.yml`
dosyasını `.github/workflows/ci.yml`'e kopyala. DİKKAT: `.github/` dokunuşu
CLAUDE.md merge-istisnası kapsamındadır → bu değişikliği içeren PR insana
sorulmadan merge EDİLMEZ. İlk çalıştırmada Godot indirme adımının loglarını
doğrula; cache aktifse sonraki koşular ~30s'dir.

## Kabul kriterleri
- [ ] `ALL TESTS PASSED` çıktısı bu oturumda üretildi (eski log kabul değil)
- [ ] Performans bütçe denetiminden geçti veya ihlaller gerekçeli istisna aldı
- [ ] Güvenlik grep'i temiz
- [ ] Karar raporunda kanıt yolu var (hangi log, hangi satır)

## Hata yolları
- `godot: command not found` → ortamda binary yok; quality-gate SONUÇSUZ
  raporlanır, asla "atlandı ama herhalde geçer" denmez.
- Import hatalarıyla flaky başlangıç → fixture'lar `--import --quit` ile ısınır
  (run_all bunu yapar); elle tek test koşarken önce
  `cd test/fixtures/save_test && godot --headless --import --quit`.
- Testler lokalde yeşil CI'da kırmızı → sürüm farkı; CI 4.6.2'ye sabitlenmiştir,
  lokal `godot --version` ile karşılaştır.

## Changelog
- 1.0.0 (2026-06-10): İlk sürüm. run_all.sh 15-adım sözleşmesi + TerrainConstants
  bütçeleri + TKT-002 path-safety geçmişinden derlendi.
