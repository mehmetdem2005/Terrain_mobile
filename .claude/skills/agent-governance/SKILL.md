---
name: agent-governance
description: .claude/agents/ altındaki 108 ajan tanımının yetki/risk denetimi — yetki matrisi üretir, ihlal arar (yetki şişmesi, çakışma matrisi boşluğu, sahipsiz worker), IMDA MGF 4 boyutuna göre raporlar. Yeni ajan eklerken, ajan yetkisi değiştirirken veya "ajanları denetle" istendiğinde kullan.
version: 1.0.0
---

# agent-governance — Ajan Filosunun Yönetişimi

## Amaç ve kapsam
`terrain-orchestrator` → 7 manager → 50 audit + 50 fix worker hiyerarşisinin
yetkilerini denetlemek ve değişiklikleri kontrollü yapmak. Üretici script:
`scripts/gen_agents.py` — ajan tanımları ELLE düzenlenmez, script'ten yeniden
üretilir (tek kaynak ilkesi).

## Standart izlenebilirlik matrisi
| Adım | Standart | Madde |
|---|---|---|
| 1: envanter + yetki matrisi | ISO/IEC 42001 (AI varlık envanteri) | 4.1 |
| 2: risk sınıflaması | ISO/IEC 23894 | 4.2 |
| 3: ihlal denetimi | NIST AI RMF (Map/Measure) | 4.3 |
| 3: en-az-yetki | OWASP excessive agency / Google SAIF | 4.5, 4.6 |
| 4: IMDA 4-boyut raporu | IMDA MGF for Agentic AI (Ocak 2026) | 4.10 |

## Ön koşullar
- `.claude/agents/` mevcut; `scripts/gen_agents.py` ile tanımlar senkron mu
  bilinmiyorsa önce kontrol: script'i kuru çalıştırıp diff'e bak.

## Prosedür

### 1. Envanter ve yetki matrisi çıkar
```bash
for f in .claude/agents/*.md .claude/agents/*/*.md; do
  printf '%s\t%s\t%s\n' "$f" \
    "$(sed -n 's/^[[:space:]]*tools:[[:space:]]*//p' "$f" | head -1)" \
    "$(sed -n 's/^[[:space:]]*model:[[:space:]]*//p' "$f" | head -1)"
done | column -t -s $'\t' | sort
```
Çıktıyı `docs/AGENT_AUTHORITY.md`'ye tablo olarak yaz (denetim izi).

### 2. Risk sınıflaması (bu filoya özel)
| Sınıf | Tanım | Beklenen araç seti | Filo karşılığı |
|---|---|---|---|
| R1 | Salt-okur analiz | Read, Grep, Glob (+Bash salt-okur) | 50 audit worker |
| R2 | Kod yazan | R1 + Edit, Write | 50 fix worker |
| R3 | Delegasyon yetkili | R2 + Agent | 7 manager |
| R4 | Tepe orkestrasyon | Agent, Read, Bash, Grep, Glob (kod YAZMAZ) | terrain-orchestrator |

### 3. İhlal denetimi — her biri için kontrol komutu
- **Yetki şişmesi:** audit worker'da `Edit`/`Write` var mı?
  `grep -l 'tools:.*\(Edit\|Write\)' .claude/agents/audit/*.md` → çıktı BOŞ olmalı.
- **Orkestratör kod yazıyor mu:** orchestrator tanımında Edit/Write OLMAMALI
  (tanım gereği "asla kendi başına kod yazma").
- **Çakışma matrisi boşluğu:** her manager'ın fix listesindeki worker'lar,
  manager'ın çakışma matrisinde anılan dosyalara yazıyor mu? node.gd/plugin.gd'ye
  yazan iki worker'ın AYNI dalga içinde paralel işaretlenmesi ihlaldir.
- **Sahipsiz worker:** her `audit/*.md` ve `fix/*.md` tam bir manager'ın
  listesinde geçmeli: `grep -rL "$(basename worker .md)" .claude/agents/managers/`
  mantığıyla tara; sahipsiz worker = çağrılamayan ölü tanım VEYA yetim yetki.
- **Model israfı:** worker'lar sonnet/haiku olmalı; worker'da `model: opus`
  bütçe ihlali olarak raporlanır (orchestrator hariç).

### 4. IMDA MGF 4-boyut uygunluk raporu
1. **Riski önden sınırla:** her ajanın `tools:` listesi görevin asgarisi mi?
2. **İnsan hesap verebilirliği:** hangi kararlar insana dönüyor? (CLAUDE.md
   merge istisnaları + bu skill'in "değişiklik prosedürü" adımı)
3. **Teknik kontroller:** fix dalgası sonrası quality-gate zorunlu mu?
   (orchestrator Phase 5 bunu kodlar — değişmediğini doğrula)
4. **Son-kullanıcı sorumluluğu:** V22_STATUS/HANDOFF güncel mi — sahip her
   oturumda filonun ne yaptığını okuyabilmeli.

### 5. Değişiklik prosedürü (yeni ajan / yetki değişimi)
1. Değişikliği `scripts/gen_agents.py`'de yap, tanımları yeniden üret.
2. Bu skill'in 3. adım denetimini çalıştır — yeni ihlal yok.
3. `docs/AGENT_AUTHORITY.md` matrisini yeniden üret.
4. Commit mesajında yetki değişimini AÇIKÇA yaz:
   `chore(agents): grant Edit to fix-extract-foliage (R1→R2), gerekçe: ...`
   Sessiz yetki genişletme = excessive agency ihlali.

## Kabul kriterleri
- [ ] `docs/AGENT_AUTHORITY.md` güncel (bu denetimde yeniden üretildi)
- [ ] 3. adımdaki 5 denetimin 5'i temiz veya ihlaller gerekçeli istisna kaydıyla
- [ ] gen_agents.py ↔ tanım dosyaları senkron (drift yok)

## Hata yolları
- gen_agents.py çıktısı mevcut tanımlarla uyuşmuyor (elle düzenlenmişler) →
  HANGİSİ doğru kararını sahibe sor; script'i mi tanımı mı güncelleyeceğin
  veri kaybı riski taşır, otonom seçme.
- Bir worker'ın görevi R1↔R2 sınırında belirsizse → R1'e koy; yetki GENİŞLETMEK
  gerekçe ister, daraltmak istemez (en-az-yetki varsayılanı).

## Changelog
- 1.0.0 (2026-06-10): İlk sürüm. 108-ajan filosunun mevcut hiyerarşisi +
  manager çakışma matrisi deseninden derlendi.
