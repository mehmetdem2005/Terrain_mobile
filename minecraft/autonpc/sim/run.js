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

// ---------- özet ----------
const fails = results.filter((r) => !r.ok);
console.log(`\n${results.length - fails.length}/${results.length} PASS`);
if (__errors.length) { console.log("RUNTIME HATALARI:"); for (const e of __errors.slice(0, 5)) console.log("  " + e.split("\n")[0]); }
if (fails.length) { console.log("SIM_FAILED"); process.exit(1); }
console.log("SIM_OK");
