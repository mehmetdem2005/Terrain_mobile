---
name: mobile-compliance
description: Shader, bellek, dokunmatik UI ve dosya-erişim değişikliklerini mobil platform standartlarına (GLES uyumluluğu, Play policy izin minimizasyonu, erişilebilirlik, bellek bütçesi) karşı denetler. terrain.gdshader'a dokunan, UI paneli ekleyen veya map_size/bellek davranışını değiştiren her işte kullan.
version: 1.0.0
---

# mobile-compliance — Mobil Hedef Uyumluluk Denetimi

## Amaç ve kapsam
Eklenti **Mobile rendering method + Android** hedefli oyunlarda çalışır; masaüstü
editörde geçen her şey cihazda geçmez. Bu skill dört denetim alanını kapsar:
shader taşınabilirliği, bellek bütçesi, dokunmatik UI, izin/dosya hijyeni.

## Standart izlenebilirlik matrisi
| Alan | Standart | Madde |
|---|---|---|
| Shader taşınabilirliği | Khronos (Vulkan/GLES) | 3.6 |
| İzin/dosya hijyeni | Google Play Developer Policy + OWASP ASVS | 3.2, 2.3 |
| Dokunmatik UI | CVAA/XAG erişilebilirlik | 3.5 |
| Bellek bütçesi | ISO/IEC 25010 performans önceliği | 1.6 |
| Veri toplama yasağı | GDPR/KVKK/COPPA | 3.4 |

## Ön koşullar
- Diff'in hangi alana dokunduğunu belirle; yalnız ilgili bölümleri koş
  (4'ü birden yalnız release öncesi tam denetimde).

## Prosedür

### A. Shader değişikliği (`addons/mobile_terrain/shaders/terrain.gdshader`)
- [ ] `render_mode` Mobile renderer'da desteklenmeyen özellik içermiyor
  (örn. `sss_mode_*`; refraction/clearcoat mobile'da sessizce düşer — davranış
  farkını CHANGES'a yaz).
- [ ] Sampler sayısı: terrain shader'ı slot başına albedo+normal+roughness+AO
  kullanır; toplam sampler GLES alt sınırı 16'yı AŞAMAZ. Say:
  `grep -c 'uniform sampler2D' addons/mobile_terrain/shaders/terrain.gdshader`
- [ ] `highp` gerektiren hesap (dünya-uzayı yükseklik karşılaştırmaları) açıkça
  `highp` işaretli — Mali/Adreno'da `mediump` varsayılanı 1024+ map'te banding yapar.
- [ ] Dallanma: fragment'ta texture'a bağlı dinamik branch eklemek yerine `mix()`.
- [ ] Doğrulama: `test/run_visual.sh` render testleri (render_shader_blend,
  render_slope_triplanar, render_slot_coherence) referans görüntülerle karşılaştır.

### B. Bellek bütçesi (map_size / splatmap / heightmap işleri)
Bellek matematiği — değişiklik bu sayıları büyütüyorsa gerekçelendir:
- height_data: `map_size² × 4 byte` (PackedFloat32Array) → 1280² ≈ 6.5 MB
- splatmap RGBA8: `map_size² × 4 byte` → 1280² ≈ 6.5 MB
- chunk mesh'leri: vertex başına ~32 byte × (chunk_size+1)² × chunk sayısı
- [ ] 2048² üstü toplam ayak izi ~%50 artar; `W_LARGE_HEIGHTMAP` (MT-W07) eşiği
  hâlâ doğru uyarıyor mu kontrol et.
- [ ] Undo snapshot'ları FULL kopya almıyor (bölgesel dirty-rect deseni korunur,
  `editor/undo_recorder.gd`).

### C. Dokunmatik / erişilebilirlik (plugin UI panelleri)
- [ ] Yeni Button/Slider dokunma hedefi ≥ 44×44 px (`custom_minimum_size`).
- [ ] Durum YALNIZ renkle gösterilmiyor (seçili fırça/slot: renk + çerçeve/ikon).
- [ ] Slider'lar klavyesiz kullanılabilir (dokunmatik sürükleme adımı mantıklı:
  brush radius 1.0-50.0 aralığında step 0.5'ten kaba değil).
- [ ] Kullanıcıya görünen string'ler Türkçe ve MT-kodlu (katalogdan, gömme değil).

### D. İzin ve dosya hijyeni
```bash
grep -rnE 'OS\.execute|HTTPRequest|TCPServer|UDPServer|upnp' addons/mobile_terrain/  # boş olmalı
grep -rnE 'FileAccess\.open\("(/|[A-Z]:)' addons/mobile_terrain/                      # boş olmalı
```
- [ ] Tüm yazma `res://terrain_data/` (TERRAIN_DATA_DIR) veya `user://` altına;
  kullanıcı girdisinden gelen yol `test/unit/test_path_safety.gd` kapsamında.
- [ ] Telemetri/analitik kodu YOK (GDPR/KVKK: eklenti veri toplamaz; eklenecekse
  sahip kararı + README beyanı gerekir, otonom eklenmez).

## Kabul kriterleri
- [ ] Dokunulan alanların checklist'i işaretli, atlanan alanlar "kapsam dışı" gerekçeli
- [ ] D bölümü grep'leri boş
- [ ] Shader değiştiyse görsel testler referansla uyumlu
- [ ] Bellek büyüten değişiklik CHANGES.md'de sayısal etkisiyle beyan edildi

## Hata yolları
- Görsel test referans görüntüsü meşru olarak değiştiyse: yeni referansı
  ÜRET ve diff'te görüntüyü değişiklik gerekçesiyle birlikte commit'le —
  referansı silmek/testi kapatmak yasak.
- Sampler limiti aşılıyorsa: yeni özellik slot sayısını düşürerek değil,
  texture array'e geçiş tasarımıyla çözülür → bu MAJOR iş, extract-system +
  sahip onayı gerektirir.

## Changelog
- 1.0.0 (2026-06-10): İlk sürüm. terrain.gdshader + TerrainConstants bellek
  modeli + W_TEXTURE_SLOT_CAP/W_LARGE_HEIGHTMAP davranışlarından derlendi.
