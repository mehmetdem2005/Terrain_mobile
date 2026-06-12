/**
 * AutoNPC v5.0 — balıkçılık. Su kıyısı bulur, oltayı sallar (gerçek olta
 * item'i + animasyon), bekler, yakalar. Bobber entity'si NPC'ye bağlanamadığı
 * için yakalama süre+loot tablosuyla simüle edilir (PLAN_V5 dürüst sınırlar).
 */
import { finishTask, countInv, addInv } from "../core/state.js";
import { craft } from "../core/recipes.js";
import { scanStep, resetScan } from "../work/scanner.js";
import { blockIdAt, playSoundAt } from "../sys/blocks.js";
import { walkTo, faceBlock } from "../nav/locomotion.js";
import { equipMainhand } from "../sys/equipment.js";
import { isPassable } from "../core/registry.js";
import { pushSubTask } from "../core/state.js";

const LOOT = [
  [0.55, "minecraft:cod"], [0.80, "minecraft:salmon"], [0.87, "minecraft:string"],
  [0.93, "minecraft:bone"], [0.97, "minecraft:leather_boots"], [1.01, "minecraft:pufferfish"],
];

export function tickFish(worker, st, data) {
  data.caught = data.caught ?? 0;
  const want = data.amount ?? 5;
  if (data.caught >= want) { resetScan(worker.id, "fish"); return finishTask(st, `Balık tamam x${data.caught}`); }

  if (countInv(st, "minecraft:fishing_rod") < 1) {
    const r = craft(st, "minecraft:fishing_rod");
    if (!r.ok) {
      if (r.missing.item === "minecraft:string") return pushSubTask(st, "hunt", { animal: "any", amount: 2, reason: "string-örümcek/balık" });
      return pushSubTask(st, "gather_wood", { tree: "any", amount: 2, reason: "olta" });
    }
  }

  if (!data.spot) {
    const r = scanStep(worker, "fish", 16, (id, pos) =>
      id === "minecraft:water" && isPassable(blockIdAt(worker.dimension, { x: pos.x, y: pos.y + 1, z: pos.z })));
    if (r.scanning) { st.status = "Su aranıyor"; return; }
    if (!r.found) return finishTask(st, "Yakında su yok");
    data.spot = r.found;
    st.dirty = true;
  }

  // kıyıya yürü
  const spot = data.spot;
  const w = walkTo(worker, { x: spot.x, y: spot.y + 1, z: spot.z }, { reach: 2, arrive: 2.5 });
  if (w.blocked) { data.spot = undefined; return; }
  if (!w.reached && w.moving) { st.status = "Su kıyısına yürüyor"; return; }

  if (st.held !== "minecraft:fishing_rod") equipMainhand(worker, st, "minecraft:fishing_rod");
  faceBlock(worker, spot);

  if (data.wait === undefined) {
    data.wait = 60 + Math.floor(Math.random() * 80);
    try { worker.playAnimation("animation.autonpc.worker.attack"); } catch (e) { /* opsiyonel */ }
    playSoundAt(worker.dimension, "random.bow", spot, 0.3);
    st.status = "Olta suda; bekliyor";
    return;
  }
  if (--data.wait > 0) { st.status = `Balık bekleniyor (${data.wait})`; return; }
  data.wait = undefined;
  const roll = Math.random();
  const item = LOOT.find(([p]) => roll < p)?.[1] ?? "minecraft:cod";
  addInv(st, item, 1);
  data.caught++;
  st.dirty = true;
  playSoundAt(worker.dimension, "random.splash", spot, 0.6);
  st.status = `Yakaladı: ${item.replace("minecraft:", "")} (${data.caught}/${want})`;
}
