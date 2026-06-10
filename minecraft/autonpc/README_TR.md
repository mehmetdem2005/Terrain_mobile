# AutoNPC PlayerAI v4.0 — komple yeniden yazım

v3.0'ın davranış birebir korunarak sıfırdan kodlanmış hali. Kurulum:
`dist/AutoNPC_PlayerAI_v4_0.mcaddon` dosyasını aç (Minecraft Bedrock 1.21.70+).
Eski v3.0 paketlerini dünyadan KALDIR (farklı UUID/namespace; çakışmaz ama
iki NPC sistemi birden karışıklık yaratır).

## v3 → v4'te düzeltilen kritik hatalar
| # | Hata | v4 çözümü |
|---|---|---|
| D1 | State RAM'de — dünya kapanınca envanter/görev/skill SIFIRLANIYORDU | Entity dynamic property'de kalıcı JSON (`core/persist.js`) |
| D2 | `runCommandAsync` API 2.0'da kaldırıldı — doğal drop + el eşyası zinciri sessizce ölüydü | Sync `runCommand` + `EquippableComponent` API |
| D3 | Hareket knockback/impulse hack'i — takılma, merdiven çıkamama | Grid **A\*** (basamak 1, düşüş ≤3, sıvı/lav kaçınma) + deterministik yol takibi |
| D4 | Panel olayları 2-3 kez abone — panel üst üste açılıyordu | Tek abonelik + oyuncu-başına debounce |
| D5 | `random_stroll` görev sırasında NPC'yi işten kaçırıyordu | Davranış dosyası sadeleşti; hareketi yalnız script yönetir |
| D6 | O(r³) tarama tek tick'te + "en yakın" önyargılı | Devam-edebilir kabuk tarayıcı, tick başına 350 blok bütçesi |
| D7 | pushSubTask/scanWait 3 dosyada kopyaydı | `core/state.pushSubTask` + `jobs/job.js` ortak taban |
| D8 | Form hataları yutulurdu | UserBusy dahil raporlanır |
| D9 | Harvest kuralı yazılmış ama HİÇ çağrılmıyordu | Yanlış alet = drop yok (gerçek oyuncu kuralı) |
| D10 | Ev inşaatı uzaktan setType basıyordu | Bloğa yürü → malzeme düş → yerleştir (RealWork) |
| + | `scriptEventReceive` yanlış kaynaktan (world) dinleniyordu | `system.afterEvents` (doğru API) |

## Kullanım
- Yeni oyuncuya kitap otomatik gelir; gelmezse `npc kitap`.
- İşçi: kitap menüsü → "İşçi oluştur" veya `npc işçi`.
- İşçiye etkileşim = Görev Paneli (envanter, odun/blok/maden/ev görevleri, oto mod).
- Chat: `npc yardım` tüm komutları listeler.

## Geliştirme
- Kaynak: `BP/scripts/` (21 ES modülü; katmanlar: core → sys → nav/work → jobs → ui/chat)
- Doğrulama: `python3 tools/validate.py` (JSON lint, UUID, BP↔RP kimlik eşleşmeleri, import grafiği)
- Paket: `bash tools/build_mcaddon.sh` → `dist/AutoNPC_PlayerAI_v4_0.mcaddon`
- Plan: `PLAN.json` (analiz + mimari + adımlar)

## v5.0 — "gerçek oyuncu" genişlemesi (PLAN_V5.json)
Yeni yetenekler (hepsi RealWork: yürü→yap→topla):
- **Savaş:** kılıç craft+vanilla hasar tablosu, YAY+OK (gerçek projektil), hostil
  radar; **creeper yaklaşınca kalkan açar** ve geri çekilir; zırh craft+kuşanma
  (gerçek equippable görseli) + vanilla-benzeri hasar azaltımı
- **Av:** inek/koyun/at/lama... öldürür (gerçek loot düşer), toplar
- **Balıkçılık:** su bulur, yüzer (A* su hücreleri), olta sallar, yakalar
- **Alan seçimi:** elinde ÇUBUKLA 2 köşe → partikül HOLOGRAM çerçeve;
  `npc düzleştir` kazar, `npc doldur` creeper çukurlarını doldurur
- **Hazine:** yakın sandıkları bulur, GERÇEK container API ile yağmalar, döner
- **Zikzak merdiven maden** + her 6 basamakta meşale
- **Ev v2:** üçgen çatı, kapı, 2 sandık+craft masası+fırın+yatak; fazla eşyayı
  sandığa GERÇEK koyar; büyü masası (malzeme varsa) yapar+yerleştirir
- **Nether görevi:** elmas kazma→obsidyen→portal İNŞA eder→Nether'e geçer→
  ancient debris arar; yoksa YATAĞI 9 BLOK İLERİYE koyup gerçek patlama ile
  (createExplosion) debris çıkarır→scrap→ingot→NETHERITE alet+zırh→eve döner
- **Oto mod yönetmeni:** odun→alet→demir→savaş seti→ev→elmas→büyü masası→
  yün/yatak→altın→NETHER→netherite (tam oyuncu ilerleyişi)
- **Sohbet:** yakındayken chat'e yaz; durum/envanter farkındalıklı TR cevap

Dürüst sınırlar (PLAN_V5.json): vanilla çatlak overlay + gerçek shield-block
mekaniği + /locate çıktısı + bobber AI'sı custom entity'ye kapalı — bunlar
birebir API yerine en yakın gerçek-etki simülasyonuyla yapıldı.
