/**
 * AutoNPC DERİN DENETİM AĞI — addon'u Minecraft olmadan boot edip sanal
 * dünyada koşturur ve davranışı ASSERT eder.
 *
 *  S1  boot: chatSend BETA-fırlatırken (gerçek stabil istemci) tick yine çalışır
 *  S2  hareket: walk_test ile NPC GERÇEKTEN yürür ve hedefe varır
 *  S3  odun: ağacı bulur, kırar (bloklar air olur), drop'u toplar (envanter)
 *  S4  kalıcılık: state kaydet/yükle kayıpsız
 *  S5  komut yüzeyi: scriptevent köprüsünden emir işler (chat'siz cihaz)
 *  S6  tehdit: yakındaki "creeper" kalkan penceresi açtırır
 *
 * Çalıştırma: node sim/run.js   (minecraft/autonpc kökünden)
 */
import { __mock, __makePlayer, __errors, world, system } from "@minecraft/server";

const results = [];
function check(name, cond, detail = "") {
  results.push({ name, ok: !!cond, detail });
  console.log(`${cond ? "PASS" : "FAIL"}  ${name}${detail ? "  [" + detail + "]" : ""}`);
}

// ---------- dünya kurulumu ----------
const dropFor = (await import("../BP/scripts/core/registry.js")).dropFor;
__mock.dropResolver = dropFor;
const ow = world.getDimension("overworld");
// ağaç: (6,64..67,3) gövde + tepesinde yaprak
for (let y = 64; y <= 67; y++) ow.setBlockId(6, y, 3, "minecraft:oak_log");
for (let dx = -1; dx <= 1; dx++) for (let dz = -1; dz <= 1; dz++) ow.setBlockId(6 + dx, 68, 3 + dz, "minecraft:oak_leaves");

const player = __makePlayer("Mehmet", { x: 0.5, y: 64, z: 0.5 }, ow);

// ---------- S1: boot (chatSend beta-fırlatır AÇIK) ----------
await import("../BP/scripts/main.js");
__mock.tick(25); // hoşgeldin runTimeout dahil
const events = await import("../BP/scripts/sys/events.js");
const diag = events.diagReport();
check("S1a boot: tick döngüsü kuruldu", __mock.intervals.length >= 1, `interval=${__mock.intervals.length}`);
check("S1b boot: chatSend tanıya 'pasif' düştü ama init ölmedi",
  diag.some((d) => d.name === "chatSend" && !d.ok) && diag.some((d) => d.name === "itemUse" && d.ok));
check("S1c boot: modül hataları yok", __errors.length === 0, __errors[0]?.slice(0, 120) ?? "");

// ---------- işçi yarat ----------
const workers = await import("../BP/scripts/sys/workers.js");
const persist = await import("../BP/scripts/core/persist.js");
const stateMod = await import("../BP/scripts/core/state.js");
const w = workers.spawnWorker(player);
check("S1d işçi spawn", !!w && w.typeId === "autonpc:worker");
const st = persist.loadState(w);

// ---------- S2: yürüme ----------
stateMod.setTask(st, "walk_test", { target: { x: 9, y: 64, z: 9 } });
const start = { ...w.location };
__mock.tick(600);
const moved = Math.hypot(w.location.x - start.x, w.location.z - start.z);
check("S2a NPC gerçekten hareket etti", moved > 5, `mesafe=${moved.toFixed(2)}`);
check("S2b hedefe vardı (görev bitti)", !st.task && /tamamlandı/i.test(st.status), st.status);

// ---------- S3: odun görevi ----------
stateMod.setTask(st, "gather_wood", { tree: "oak", amount: 3 });
__mock.tick(6000);
const logsLeft = [64, 65, 66, 67].filter((y) => ow.getBlockId(6, y, 3) === "minecraft:oak_log").length;
check("S3a ağaç blokları gerçekten kırıldı", logsLeft <= 1, `kalan log=${logsLeft}`);
check("S3b drop'lar toplandı (sanal envanter)", stateMod.countInv(st, "minecraft:oak_log") >= 3,
  `oak_log=${stateMod.countInv(st, "minecraft:oak_log")}`);
check("S3c görev tamamlandı", !st.task || st.task.type !== "gather_wood", st.status);
check("S3d tick hatasız", __errors.length === 0, __errors[0]?.slice(0, 120) ?? "");

// ---------- S4: kalıcılık ----------
persist.saveState(w, st);
stateMod.dropCachedState(w.id);
const st2 = persist.loadState(w);
check("S4 kalıcılık: envanter+görev korunur",
  stateMod.countInv(st2, "minecraft:oak_log") === stateMod.countInv(st, "minecraft:oak_log")
  && st2.owner === "Mehmet");

// ---------- S5: scriptevent komut köprüsü (chat'siz cihaz yolu) ----------
system.afterEvents.scriptEventReceive.fire({ id: "autonpc:cmd", message: "blok stone 2", sourceEntity: player });
__mock.tick(2);
const st3 = persist.loadState(w);
check("S5 scriptevent ile emir işledi", st3.task?.type === "collect_block",
  `task=${st3.task?.type}`);
stateMod.stopAll(st3);

// ---------- S6: creeper kalkan refleksi ----------
const threats = await import("../BP/scripts/combat/threats.js");
stateMod.addInv(st3, "minecraft:shield", 1);
ow.spawnEntity("minecraft:creeper", { x: w.location.x + 2, y: w.location.y, z: w.location.z });
__mock.tick(3);
check("S6 creeper → kalkan penceresi", (threats.shieldWindows.get(w.id) ?? 0) > 0,
  `pencere=${threats.shieldWindows.get(w.id)}`);
// S6 izolasyonu: creeper'ı kaldır (mock'ta patlamaz; S7+ görevlerini bloklamasın)
for (const e of ow.getEntities({ type: "minecraft:creeper" })) e.remove();
__mock.tick(60); // kalkan penceresi sönsün

// ---------- özet ----------
const fails = results.filter((r) => !r.ok);
console.log(`\n${results.length - fails.length}/${results.length} PASS`);
if (__errors.length) { console.log("RUNTIME HATALARI:"); for (const e of __errors.slice(0, 5)) console.log("  " + e.split("\n")[0]); }
if (fails.length) { console.log("SIM_FAILED"); process.exit(1); }
console.log("SIM_OK");

// ================= GENİŞLETİLMİŞ DENETİM AĞI (v5.0.2) =================

// ---------- S7: ev inşaatı (çatı + sandığa depolama) ----------
stateMod.addInv(st3, "minecraft:oak_log", 50);
stateMod.addInv(st3, "minecraft:cobblestone", 40);
stateMod.addInv(st3, "minecraft:dirt", 40); // sandığa gidecek fazlalık
st3.base = { x: 20, y: 64, z: 20 };
stateMod.setTask(st3, "build_house", {});
__mock.tick(9000);
const roofMid = ow.getBlockId(20, 64 + 3 + 3, 20); // mahya
const chestId = ow.getBlockId(18, 65, 22);
check("S7a ev: mahya bloğu kondu", roofMid === "minecraft:oak_planks", roofMid);
check("S7b ev: sandık kondu", chestId === "minecraft:chest", chestId);
check("S7c ev görevi bitti + flag", st3.flags?.houseBuilt === true, st3.status);
const chestCont = ow.getBlock({ x: 18, y: 65, z: 22 })?.getComponent("minecraft:inventory")?.container;
const chestHas = chestCont ? chestCont.slots.filter(Boolean).length : 0;
check("S7d fazla eşya GERÇEK sandığa kondu", chestHas > 0, `slot=${chestHas}`);

// ---------- S8: av (gerçek ölüm + ganimet toplama) ----------
stateMod.stopAll(st3);
ow.spawnEntity("minecraft:cow", { x: Math.floor(w.location.x) + 4.5, y: 64, z: Math.floor(w.location.z) + 0.5 }); // ZEMINDE (mock yerçekimsiz)
const leatherBefore = stateMod.countInv(st3, "minecraft:leather");
stateMod.setTask(st3, "hunt", { animal: "cow", amount: 1 });
__mock.tick(1500);
check("S8a inek avlandı (görev bitti)", !st3.task || st3.task.type !== "hunt", st3.status);
check("S8b ganimet toplandı", stateMod.countInv(st3, "minecraft:leather") > leatherBefore,
  `deri=${stateMod.countInv(st3, "minecraft:leather")}`);

// ---------- S9: alan düzleştirme + çukur doldurma ----------
stateMod.stopAll(st3);
for (let x = 30; x <= 33; x++) for (let z = 30; z <= 33; z++) ow.setBlockId(x, 64, z, "minecraft:stone"); // tümsek
ow.setBlockId(31, 62, 31, "minecraft:air"); // creeper çukuru
ow.setBlockId(31, 61, 31, "minecraft:air");
stateMod.setTask(st3, "flatten", { region: { min: { x: 30, y: 63, z: 30 }, max: { x: 33, y: 64, z: 33 } }, level: 63 });
__mock.tick(8000);
const bumpLeft = [...Array(4)].flatMap((_, i) => [...Array(4)].map((_, j) => ow.getBlockId(30 + i, 64, 30 + j)))
  .filter((id) => id === "minecraft:stone").length;
check("S9a tümsek kazıldı", bumpLeft === 0, `kalan=${bumpLeft}`);
check("S9b çukur dolduruldu", ow.getBlockId(31, 62, 31) !== "minecraft:air", ow.getBlockId(31, 62, 31));

// ---------- S10: KAOS — görev ortasında dünyayı boz ----------
stateMod.stopAll(st3);
for (let y = 64; y <= 67; y++) ow.setBlockId(40, y, 40, "minecraft:oak_log");
stateMod.setTask(st3, "gather_wood", { tree: "oak", amount: 2 });
const errBefore = __errors.length;
for (let i = 0; i < 4000 && st3.task?.type === "gather_wood"; i += 25) {
  __mock.tick(25);
  if (i % 100 === 0) {
    ow.setBlockId(40, 64 + (i / 100) % 4, 40, "minecraft:air");
    for (const e of ow.getEntities({ type: "minecraft:item" })) if (Math.random() < 0.5) e.remove();
    if (i % 400 === 0) w.teleport({ x: w.location.x + 2, y: 64, z: w.location.z - 2 }, {});
  }
}
__mock.tick(2000);
check("S10a kaos altında çökme yok", __errors.length === errBefore, __errors.slice(errBefore)[0]?.slice(0, 100) ?? "");
check("S10b kaos sonrası görev düşmedi/takılmadı (bitti veya watchdog kurtardı)",
  !st3.task || st3.task.type !== "gather_wood" || /yeniden|watchdog/i.test(st3.status), st3.status);

// ---------- S11: SOAK — 2 işçi, 20.000 tick otomatik mod ----------
for (let y = 64; y <= 66; y++) { ow.setBlockId(-10, y, -10, "minecraft:oak_log"); ow.setBlockId(-14, y, -8, "minecraft:oak_log"); }
ow.setBlockId(-12, 63, -12, "minecraft:iron_ore");
ow.setBlockId(-12, 63, -13, "minecraft:coal_ore");
const w2 = workers.spawnWorker(player);
w2.teleport({ x: -8, y: 64, z: -8 }, {});
const stA = persist.loadState(w); const stB = persist.loadState(w2);
stateMod.stopAll(stA); stateMod.stopAll(stB);
stA.auto = true; stB.auto = true;
const errSoak = __errors.length;
__mock.blockReadStats.max = 0; __mock.blockReadStats.total = 0; __mock.blockReadStats.ticks = 0;
__mock.tick(20000);
const invA = Object.values(stA.inventory).reduce((a, b) => a + b, 0);
const invB = Object.values(stB.inventory).reduce((a, b) => a + b, 0);
const avgReads = (__mock.blockReadStats.total / Math.max(1, __mock.blockReadStats.ticks)).toFixed(0);
check("S11a soak 20k tick: sıfır runtime hatası", __errors.length === errSoak, __errors.slice(errSoak)[0]?.slice(0, 100) ?? "");
check("S11b iki işçi de üretken (envanter büyüdü)", invA > 0 && invB > 0, `A=${invA} B=${invB}`);
check("S11c tick bütçesi: ort. blok-okuma sınırda", Number(avgReads) < 3000, `ort=${avgReads}/tick max=${__mock.blockReadStats.max}`);
check("S11d hiçbir işçi 'Hata:' durumunda değil", !/^Hata:/.test(stA.status) && !/^Hata:/.test(stB.status), `A='${stA.status}' B='${stB.status}'`);

// ---------- yeniden özet ----------
{
  const f2 = results.filter((r) => !r.ok);
  console.log(`\nTOPLAM ${results.length - f2.length}/${results.length} PASS`);
  if (f2.length) { console.log("SIM_FAILED"); process.exit(1); }
  console.log("SIM_OK_FULL");
}

// ========== v5.1 MÜHENDİS MODU EĞİTİM SENARYOLARI ==========

// ---------- S12: DUVAR — kazarak geç ----------
stateMod.stopAll(stA);
w.teleport({ x: 100.5, y: 64, z: 100.5 }, {});
for (let z = 60; z <= 140; z++) for (let y = 64; y <= 69; y++) ow.setBlockId(103, y, z, "minecraft:stone"); // SONSUZ duvar (dolaşılamaz)
stateMod.setTask(stA, "walk_test", { target: { x: 107, y: 64, z: 100 } });
__mock.tick(3000);
const holePunched = ow.getBlockId(103, 64, 100) !== "minecraft:stone" || ow.getBlockId(103, 65, 100) !== "minecraft:stone";
check("S12a duvar: tünel açıldı", holePunched);
check("S12b duvar: hedefe ulaşıldı", Math.abs(w.location.x - 107.5) < 2.5 && !stA.task, `x=${w.location.x.toFixed(1)} st=${stA.status}`);

// ---------- S13: ÇUKUR — kazarak/basamakla çık ----------
stateMod.stopAll(stA);
for (let y = 58; y <= 64; y++) ow.setBlockId(120, y, 120, "minecraft:air"); // 1x1 derin kuyu
w.teleport({ x: 120.5, y: 58, z: 120.5 }, {});
stateMod.setTask(stA, "walk_test", { target: { x: 124, y: 64, z: 120 } });
__mock.tick(4000);
check("S13a çukur: yüzeye çıktı", w.location.y >= 63, `y=${w.location.y.toFixed(1)}`);
check("S13b çukur: hedefe ulaşıldı", !stA.task && /tamamlandı/i.test(stA.status), stA.status);

// ---------- S14: UÇURUM — köprü kur ----------
stateMod.stopAll(stA);
w.teleport({ x: 140.5, y: 64, z: 140.5 }, {});
for (let x = 142; x <= 146; x++) for (let z = 100; z <= 180; z++) for (let y = 40; y <= 63; y++) ow.setBlockId(x, y, z, "minecraft:air"); // UZUN kanyon (dolaşılamaz)
stateMod.addInv(stA, "minecraft:cobblestone", 16);
stateMod.setTask(stA, "walk_test", { target: { x: 149, y: 64, z: 140 } });
const minY = { v: 99 };
for (let i = 0; i < 4000; i += 10) { __mock.tick(10); minY.v = Math.min(minY.v, w.location.y); if (!stA.task) break; }
check("S14a uçurum: düşmedi", minY.v >= 63, `minY=${minY.v.toFixed(1)}`);
check("S14b uçurum: köprüyle geçti", Math.abs(w.location.x - 149.5) < 2.5, `x=${w.location.x.toFixed(1)} st=${stA.status}`);
check("S14c köprü blokları gerçekten döşendi", [142,143,144,145,146].some((x)=>ow.getBlockId(x,63,140)==="minecraft:cobblestone"));

// ---------- S15: LAV — mühürle ve güvenle geç ----------
stateMod.stopAll(stA);
w.teleport({ x: 160.5, y: 64, z: 160.5 }, {});
for (let x = 162; x <= 164; x++) for (let z = 130; z <= 190; z++) ow.setBlockId(x, 63, z, "minecraft:lava"); // GENİŞ lav nehri (dolaşılamaz)
stateMod.addInv(stA, "minecraft:cobblestone", 16);
const hpBefore = w.health.cur;
stateMod.setTask(stA, "walk_test", { target: { x: 167, y: 64, z: 160 } });
__mock.tick(4000);
check("S15a lav: hasarsız geçiş", w.health.cur >= hpBefore, `hp=${w.health.cur}`);
check("S15b lav: hedefe ulaşıldı", Math.abs(w.location.x - 167.5) < 2.5 && !stA.task, `x=${w.location.x.toFixed(1)} st=${stA.status}`);
check("S15c lav mühürlendi/kapaklandı", [162,163,164].some((x)=>ow.getBlockId(x,63,160)==="minecraft:cobblestone"));

// ---------- mühendis sonrası nihai özet ----------
{
  const f3 = results.filter((r) => !r.ok);
  console.log(`\nNİHAİ ${results.length - f3.length}/${results.length} PASS`);
  if (__errors.length) { console.log("RUNTIME:"); for (const e of __errors.slice(0,3)) console.log("  "+e.split("\n")[0]); }
  if (f3.length) { console.log("SIM_FAILED"); process.exit(1); }
  console.log("SIM_OK_ENGINEER");
}

