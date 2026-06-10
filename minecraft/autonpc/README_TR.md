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

## v5.0.1 — KÖK NEDEN DÜZELTMESİ + derin denetim ağı
**"NPC hiç kıpırdamıyor / emir işlemiyor" kök nedeni:** `main.js` önce olayları
bağlıyordu ve `chatSend` before-event'i STABIL API'de yok (beta-gated) →
subscribe fırlatınca init ölüyor → `startTick()` hiç çağrılmıyordu = tamamen
cansız NPC. (v3 her subscribe'ı tek tek try'a sarıyordu; v4 temizliği bu
korumayı söküp hatayı ölümcülleştirmişti.)

Kök çözümler:
1. `startTick()` HER ŞEYDEN ÖNCE + korumalı; her olay aboneliği bağımsız
   `sub()` zarfında — biri yoksa diğerleri ve tick YAŞAR (`npc tanı` raporlar)
2. Chat'siz cihaz köprüsü: `/scriptevent autonpc:cmd <komut>` ile TÜM npc
   komutları; panel + kitap zaten olaysız çalışır
3. Manifest modülleri 2.0.0 → **1.17.0 / 1.3.0** (tüm 1.21.70+ stabilde mevcut)
4. Entity: knockback_resistance 1.0→0.4, pushable=true (vurunca tepki verir)

**Derin denetim ağı (`sim/`):** mock `@minecraft/server` + sanal voxel dünyası;
addon GERÇEKTEN boot edilir, sahte işçi 6 senaryoda koşturulur ve assert edilir:
boot-stabil-API, yürüyüş+varış, ağaç kırma+drop toplama, kalıcılık, scriptevent
emri, creeper-kalkan refleksi. İlk koşuda gerçek bir hata yakaladı (boş-yol =
"varıldı" yerine "blocked" sayılıyordu) — kökten düzeltildi. **13/13 PASS**;
`tools/build_mcaddon.sh` artık sim geçmeden paket ÜRETMEZ.

## v5.1.0 — MÜHENDİS MODU (videodaki 'engelde takılma'nın kök çözümü)
A* yol bulamadığında NPC artık PES ETMEZ — locomotion otomatik mühendisliğe
düşer (nav/engineer.js): öndeki engeli GERÇEK süreyle kazar (tünel), boşluk/
lav üstüne envanterden blok döşer (köprü/mühür), hedef yukarıda veya çukura
düştüyse duvara basamak oyarak TIRMANIR, baş üstünü açar, lav komşuluğunu
önce mühürler (kendini koruma). Güvenlik: kendi ayağının altını asla kazmaz,
bedrock'ta yön değiştirir, üretken-eylemsizlik 16 yönde sürerse dürüstçe
'yol yok' der. Eğitim/kanıt senaryoları (sim S12-S15): aşılamaz duvar→tünel,
6-derin kuyu→yüzeye çıkış, 5-geniş kanyon→köprü (hiç düşmeden), lav nehri→
mühür+hasarsız geçiş. NİHAİ: 37/37 PASS — build kapısı sim'e bağlı.

## v5.2.0 — DEVRİM TURU: işbirliği, uzak görüş, kişilik, performans
- **LAG kökü:** tehdit radarı işçi başına HER tick entity sorgusuydu → 3 tick'te
  bire indi; ≥3 işçide görevler dönüşümlü tick'lerde (stagger); A* düğüm tavanı
  450, replan cooldown 35 → oto modda çoklu işçi lag'i kesildi
- **İŞBİRLİĞİ PROTOKOLÜ (sys/coop.js):** takılan işçi (watchdog/mühendis)
  İMDAT yayınlar; boştaki işçi çağrıyı sahiplenir, gider, etrafını kazıp
  kurtarır (jobs/rescue.js) — sim S16: 12 blok koşup duvarı kazdı ✓
- **UZAK GÖRÜŞ:** tarama yarıçapları 32/48/32 (bütçeli tarayıcı sayesinde
  lag'sız) — "hedef bulamıyor, duruyor" bitti
- **PİLLAR-UP:** hedef yukarıda + etraf açık + dolgu varsa blok üstüne blok
  koyarak yükselir (sim S17 ✓); mühendis zaten tünel/köprü/mühür biliyor
- **CRAFT MASASI GERÇEK:** alet/silah üretimi masasız olmaz — 6 blok içinde
  masa yoksa craft eder, YERE KOYAR, başında üretir
- **Oto akış netleşti:** odun → masa → tahta kazma → taş → TAŞ KAZMA →
  madene in (demir+kömür, zikzak+meşale) → erit → savaş seti → ...
- **KİŞİLİK:** her işçiye rastgele isim (Kazma Kemal, Somurtkan Selim...);
  olaylara asabi TR mesajlar (spawn/takılma/imdat/kurtarma/hasar/creeper)
- **SKİNLER:** worker dokusundan 3 yeni renk varyantı üretildi (PIL hue-shift);
  BP variant + spawn randomize + render controller `query.variant` → her işçi
  4 görünümden rastgele doğar
- NİHAİ: **42/42 PASS** (S16 işbirliği + S17 pillar dahil)
