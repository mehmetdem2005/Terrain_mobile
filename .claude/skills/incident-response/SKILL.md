---
name: incident-response
description: Kullanıcı bug raporunu ITIL known-error akışıyla işler — triyaj, MT-XXX tanı kodu tahsisi, kök neden, regresyon testi, hotfix ve kayıt. "Kullanıcı şu hatayı bildirdi", "şu bug'ı çöz", "MT-XXX ne demek" durumlarında kullan.
version: 1.0.0
---

# incident-response — Bug Raporundan Kalıcı Çözüme

## Amaç ve kapsam
Eklenti kullanıcısından gelen hata raporunu, kanıt zinciri kopmadan
"belirti → kök neden → fix → regresyon testi → kayıt" döngüsünden geçirmek.
Known-error veritabanı = `addons/mobile_terrain/core/terrain_diagnostics.gd`
(MT-001..MT-008 hata, MT-W01..MT-W15 uyarı kataloğu).

## Standart izlenebilirlik matrisi
| Adım | Standart | Madde |
|---|---|---|
| 1: triyaj + önem sınıfı | ITIL 4 incident yönetimi | 1.8 |
| 2: MT kodu tahsisi | ITIL known-error DB | 1.8 |
| 3: kök neden | ISO 12207 problem çözümleme | 1.3 |
| 4: regresyon testi önce | ISO 29119 | 1.7 |
| 5: hotfix sürümü | SemVer PATCH | 2.1 |
| 6: HANDOFF/CHANGES kaydı | ISO 9001 kayıt zorunluluğu | 1.10 |

## Ön koşullar
- Rapordan asgari üçlü çıkarılmış olmalı: **Godot sürümü + adım dizisi + tam
  hata metni/ekran görüntüsü**. Eksikse kullanıcıdan iste; tahminle fix yazma.

## Prosedür

### 1. Triyaj — önem matrisi
| Sınıf | Tanım | Örnek | SLA-benzeri hedef |
|---|---|---|---|
| S1 | Veri kaybı / sahne bozulması | save sonrası height_data sıfırlanıyor | aynı oturumda hotfix |
| S2 | İşlev tamamen kırık | paint hiç çalışmıyor | sonraki PATCH |
| S3 | Yanlış davranış, workaround var | erode kenarlarda taşıyor | planlı sürüm |
| S4 | Kozmetik / mesaj | yazım hatası, log gürültüsü | birikimli |

S1 şüphesinde İLK iş: kullanıcıya veri kurtarma yolu söyle
(`res://terrain_data/*.res` companion dosyaları sahneden bağımsız yaşar —
TERRAIN_DATA_DIR sözleşmesi).

### 2. Tanı kodu eşle veya tahsis et
- Rapordaki mesaj `MT-` içeriyorsa katalogdan oku: kod zaten kök neden ipucudur
  (örn. MT-004 = height_data.size ≠ map_size² → import/resize yarışı).
- Yeni hata sınıfıysa: `terrain_diagnostics.gd`'de bir SONRAKİ boş kodu al
  (hata: MT-009'dan itibaren; uyarı: MT-W16'dan itibaren — önce dosyayı oku,
  çakışma kontrolü grep'le: `grep -o 'MT-W\?[0-9]*' addons/mobile_terrain/core/terrain_diagnostics.gd | sort -V | tail -3`).
- Koda mesaj şablonu eklenir, çıplak `push_error/push_warning` YAZILMAZ —
  her şey katalogdan geçer (`TerrainDiagnostics.error(E_..., [args])`).

### 3. Kök neden — geçmişten bilinen şüpheli sınıfları
Bu projenin tekrarlayan bug aileleri (önce bunlara bak):
- **Save/persistence:** EditorInterface re-entry, inline/external geçişi
  (HANDOFF.md tüm tarihçesi; çözüm deseni save_orchestrator Plan B).
- **Paylaşılan Image referansı / lock artığı** (node.gd:2210 vakası).
- **Stroke yaşam döngüsü:** start_stroke raymarch hit'ten önce açılması
  (plugin.gd:1977 vakası), tool değişiminde cache temizliği (current_tool setter).
- **Boyut uyuşmazlığı:** map_size yeniden boyutlanırken devam eden stroke/rebuild
  (audit-chunk-resize-during-stroke ailesi).

### 4. Regresyon testini fix'ten ÖNCE yaz
- Kullanıcı senaryosunu headless yeniden üreten test: kırmızı olduğunu GÖR.
- Konum: tek-sistem ise `test/unit/test_<sistem>.gd`'ye case ekle; kullanıcı
  akışıysa `test/unit/test_user_fixes.gd` deseni (TKT-006/007 örnekleri).
- `test/run_all.sh`'a kayıtlı değilse adım ekle (`*_OK` grep sözleşmesi).

### 5. Fix + doğrulama
Minimal fix; fırsatçı refactor'ı AYNI commit'e karıştırma (o iş extract-system
skill'ine gider). Sonra `bash test/run_all.sh` → `ALL TESTS PASSED`.

### 6. Kayıt
- `CHANGES.md` "Düzeltildi" girdisi: belirti + kök neden + MT kodu + dosya:satır.
- S1/S2 ise `V22_STATUS.md`'ye not (sonraki oturum bilsin).
- Commit: `fix(<sistem>): <belirti> (MT-XXX)`.

## Kabul kriterleri
- [ ] Regresyon testi fix'siz KIRMIZI, fix'le YEŞİL gösterildi (her iki log)
- [ ] Hata mesajı TerrainDiagnostics kataloğundan geçiyor
- [ ] CHANGES.md girdisinde MT kodu + dosya:satır var
- [ ] `ALL TESTS PASSED`

## Hata yolları
- Yeniden üretilemiyor → kullanıcının map_size/heightmap boyutunu iste; bug'ların
  çoğu 1024+ boyutta tetiklenir (chunk bütçeleri devreye girer). Yeniden
  üretilemeyen bug'a fix YAZMA; enstrümantasyon ekle (yeni MT-W kodu) ve sürümle.
- Fix başka testi kırdı → kök neden yanlış katmanda; geri al, bir üst çağırana bak.
- Godot çekirdek bug'ı şüphesi → upstream issue ara (HANDOFF #87636 örneği),
  bulursan workaround'u yorumda issue linkiyle belgele.

## Changelog
- 1.0.0 (2026-06-10): İlk sürüm. TerrainDiagnostics kataloğu + CHANGES.md bug
  tarihçesi + HANDOFF vakalarından derlendi.
