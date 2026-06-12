---
name: release-engineering
description: SemVer sürüm kararı, CHANGES.md disiplini ve SLSA-provenanslı release build üretimi. "Release çıkar", "versiyon yükselt", "zip hazırla", "Asset Library'e yayınla" istendiğinde kullan. scripts/release_build.sh bu skill'in aracıdır.
version: 1.0.0
---

# release-engineering — Sürümleme ve Release Üretimi

## Amaç ve kapsam
`addons/mobile_terrain`'in dağıtılabilir, kanıt zincirli release'ini üretmek.
Elle zip YASAK — tek yol `scripts/release_build.sh` (git arşivi → kurcalanmamışlık).

## Standart izlenebilirlik matrisi
| Adım | Standart | Madde |
|---|---|---|
| 1: sürüm kararı | SemVer 2.0.0 | 2.1 |
| 2: changelog | Keep a Changelog | 2.8 |
| 3: build + provenance | SLSA L1 | 2.5 |
| 3: sbom.spdx.txt | SPDX / ISO 5962 | 2.6 |
| 4: Asset Library kontrolü | Godot Asset Library kuralları | 2.9 |
| Test kanıtı ön koşulu | ISO 29119 / IMDA MGF boyut-3 | 1.7, 4.10 |

## Ön koşullar
- quality-gate skill'i bu oturumda yeşil bitirmiş olmalı (`ALL TESTS PASSED`).
- Çalışma ağacı temiz (provenance commit'e bağlanır; kirli ağaç = belirsiz kaynak).

## Prosedür

### 1. Sürüm kararını ver (SemVer karar tablosu — bu projeye özel)
| Değişiklik | Bump | Gerekçe |
|---|---|---|
| `.tscn`/`.res` sahne formatını kıran her şey (export silme/yeniden adlandırma, external_data şema değişikliği) | **MAJOR** | Kullanıcı sahneleri kırılır; migration kodu ZORUNLU |
| Yeni araç/fırça/sistem, yeni public metod, yeni MT-kodu | **MINOR** | Geriye uyumlu özellik |
| Bug fix, performans iyileştirme, mesaj düzeltme | **PATCH** | Davranış sözleşmesi aynı |

Mevcut durum notu: `plugin.cfg` "22.0" iki parçalı — SemVer'e geçiş anında
`22.0.0` yazılır; bu kıran değişiklik DEĞİLDİR (yalnız metin formatı).

### 2. Kayıtları güncelle
- `plugin.cfg` → `version="X.Y.Z"`.
- `CHANGES.md` → en üste yeni sürüm başlığı; kategoriler: Eklendi / Değişti /
  Düzeltildi / Kaldırıldı (Keep a Changelog). Sürüm string'i AYNEN geçmeli
  (release script grep'le doğrular).
- Bu ikisini tek commit'te bağla: `chore(release): vX.Y.Z`.

### 3. Build
```bash
scripts/release_build.sh --check   # önce uyumluluk raporu
scripts/release_build.sh           # build/ altına: zip + SHA256SUMS + provenance.json + sbom.spdx.txt
```
Script'in 5 ön koşulu (SemVer, changelog kaydı, LICENSE, temiz ağaç, test kanıtı)
kırmızıysa build başlamaz. Ön koşulu HİLE ile geçme (örn. sahte log) — kanıt
zinciri release'in varlık sebebidir.

### 4. Asset Library / dağıtım kontrol listesi
- [ ] Kök `LICENSE` zip içinde
- [ ] `plugin.cfg` alanları dolu: name, description, author, version, script
- [ ] Zip yapısı `addons/mobile_terrain/...` (kök sızıntısı yok — `unzip -l` ile bak)
- [ ] `provenance.json` içindeki `sourceCommit` push'lanmış bir commit
- [ ] Git tag: `git tag -a vX.Y.Z -m "MobileTerrain3D vX.Y.Z" && git push origin vX.Y.Z`

## Kabul kriterleri
- [ ] `RELEASE_BUILD_OK` çıktısı alındı
- [ ] `sha256sum -c build/SHA256SUMS` geçiyor
- [ ] provenance.json'daki commit = `git rev-parse HEAD`
- [ ] Tag push'landı, CHANGES.md sürümle eşleşiyor

## Hata yolları
- `RELEASE_PRECHECK_FAILED: LICENSE yok` → lisans kararı SAHİBE sorulur
  (MIT önerisi sunulabilir ama lisans seçimi hukuki karardır, otonom verilmez).
- Kirli ağaç → önce commit; release commit'ine alakasız değişiklik KARIŞTIRMA.
- Test kanıtı eski oturumdan → run_all.sh'ı yeniden koştur; kanıt bayatlamaz kuralı.

## Changelog
- 1.0.0 (2026-06-10): İlk sürüm. release_build.sh ile birlikte tasarlandı.
