---
name: standards-audit
description: Repoyu docs/STANDARDS.md'ye karşı uçtan uca denetler — skill yönetişim doğrulayıcısını, release ön-kontrolünü ve boşluk-analizi tablosunu çalıştırıp günceller. "Standartlara uyuyor muyuz", periyodik denetim veya yeni skill eklendiğinde kullan. Meta-skill: skill'lerin kendisinin standartlara uyduğunu da bu doğrular.
version: 1.0.0
---

# standards-audit — Standart Uygunluk Meta-Denetimi

## Amaç ve kapsam
`docs/STANDARDS.md`'deki 40 standardın repodaki SOMUT karşılıklarını denetlemek
ve boşluk-analizi tablosunu gerçek durumla senkron tutmak. Bu skill, skill
paketinin kendi yönetişimini de kapsar (özyineli: kendi SKILL.md'si de
doğrulayıcıdan geçer).

## Standart izlenebilirlik matrisi
| Adım | Standart | Madde |
|---|---|---|
| 1: skill yapı doğrulaması | ISO 9001 (süreçlerin tanımlı + denetlenir olması) | 1.10 |
| 2: release ön-kontrol | SemVer/SLSA/SPDX/Changelog | 2.1, 2.5, 2.6, 2.8 |
| 3: ajan yönetişim denetimi | ISO 42001 / NIST AI RMF | 4.1, 4.3 |
| 4: boşluk tablosu güncelleme | TOGAF gap analizi | 1.1 |
| 5: COBIT karar-yetki kontrolü | COBIT | 1.9 |

## Ön koşullar
- `docs/STANDARDS.md` mevcut ve okunmuş (boşluk tablosu referans alınır).

## Prosedür

### 1. Skill yönetişim doğrulaması (mekanik)
```bash
bash scripts/validate_skills.sh
```
Sözleşme: her skill'de SemVer `version`, klasör-adı eşleşmesi, 5 zorunlu bölüm
(İzlenebilirlik / Prosedür / Kabul kriterleri / Hata yolları / Changelog),
referans verilen script'lerin varlığı + çalıştırılabilirliği.
Son satır `SKILL_VALIDATION_OK` değilse ihlalleri düzeltmeden devam etme.

### 2. Release uygunluk fotoğrafı
```bash
bash scripts/release_build.sh --check || true
```
Çıkan İHLAL satırları boşluk tablosunun "Eksik" sütununun ham verisidir
(SemVer formatı, LICENSE, changelog kaydı, test kanıtı).

### 3. Ajan yönetişim denetimi
agent-governance skill'inin 3. adım denetimlerini koş (5 kontrol:
yetki şişmesi, orkestratör yazma yasağı, çakışma matrisi, sahipsiz worker,
model israfı). Özet sonucu bu denetimin raporuna taşı.

### 4. Boşluk tablosunu güncelle
`docs/STANDARDS.md` sonundaki tabloyu 1-3 çıktılarıyla senkronla:
kapanan boşluğu ✓'ya çevir, yeni bulunan boşluğu satır olarak ekle.
Tablo değişmediyse dokunma (gürültü commit'i üretme).

### 5. Karar-yetki sınır kontrolü (COBIT)
Şu kararların hâlâ İNSANA ait olduğunu doğrula — herhangi bir skill/ajan/config
bunları otonom hale getirmişse İHLAL olarak raporla:
- Lisans seçimi (release-engineering hata yolu)
- `.github/`, CLAUDE.md, branch koruması değişikliklerinin merge'ü
- Telemetri/veri toplama eklenmesi (mobile-compliance D bölümü)
- gen_agents.py ↔ tanım drift'inde hangi tarafın doğru olduğu

### 6. Rapor
Tek özet tablo: alan | durum (UYUMLU/İHLAL/BOŞLUK) | kanıt (komut çıktısı/dosya).
S1 önem derecesinde ihlal varsa (örn. test kanıtı olmadan release artefaktı
push'lanmış) bunu raporun İLK satırına koy.

## Kabul kriterleri
- [ ] `SKILL_VALIDATION_OK` üretildi
- [ ] `--check` çıktısındaki her İHLAL ya kapatıldı ya boşluk tablosuna işlendi
- [ ] Boşluk tablosu ile gerçek durum arasında bilinen fark kalmadı
- [ ] Rapor kanıt yollarıyla birlikte sunuldu

## Hata yolları
- Doğrulayıcı meşru bir yapısal istisnaya takılıyorsa (örn. harici skill):
  kuralı gevşetme; `validate_skills.sh` içindeki EXEMPT listesine gerekçeli
  ekleme yap ve bu kararı commit mesajında beyan et.
- Boşluk kapatma işi büyükse (örn. CI kurulumu): bu denetim içinde YAPMA;
  ilgili skill'e (quality-gate) yönlendir, denetim raporu denetim olarak kalsın
  (denetçi-uygulayıcı ayrımı).

## Changelog
- 1.0.0 (2026-06-10): İlk sürüm. validate_skills.sh + release_build.sh --check
  ile birlikte tasarlandı.
