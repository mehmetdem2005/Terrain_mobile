/**
 * AutoNPC v4.0 — süreli blok kırma (RealWork çekirdeği).
 * registry'den süre + D9 harvest kuralı: yanlış alet = drop YOK (gerçek oyuncu kuralı).
 * Kırılınca sys/blocks.naturalBreak doğal drop üretir; drops.js pickup'ı başlatır.
 */
import { breakTicks, canHarvest, dropFor, isAir } from "../core/registry.js";
import { blockIdAt, naturalBreak, spawnItemAt, playSoundAt, particleAt } from "../sys/blocks.js";
import { faceBlock } from "../nav/locomotion.js";
import { equipBestTool } from "./tools.js";
import { startPickup } from "./drops.js";
import { keyV } from "../core/math.js";

const breaking = new Map(); // workerId -> {key, blockId, progress, total}

export function clearBreaking(workerId) { breaking.delete(workerId); }

function effects(worker, pos, blockId, progress) {
  if (progress % 8 !== 0 && progress !== 1) return;
  try { worker.playAnimation("animation.autonpc.worker.swing"); } catch (e) { /* anim opsiyonel */ }
  const sound = blockId.includes("log") ? "dig.wood" : blockId.includes("leaves") ? "dig.grass" : "dig.stone";
  playSoundAt(worker.dimension, sound, pos);
  particleAt(worker.dimension, "minecraft:basic_smoke_particle", pos);
}

/**
 * Her tick çağrılır. @returns {done, broke?, gone?, noDrop?}
 * opts.drop: beklenen drop override (engel temizleme "minecraft:air" verir → pickup yok)
 */
export function breakStep(worker, st, pos, opts = {}) {
  const dim = worker.dimension;
  const id = blockIdAt(dim, pos);
  if (isAir(id)) { breaking.delete(worker.id); return { done: true, gone: true }; }

  const k = keyV(pos);
  let b = breaking.get(worker.id);
  if (!b || b.key !== k || b.blockId !== id) {
    b = { key: k, blockId: id, progress: 0, total: 0 };
    breaking.set(worker.id, b);
  }
  equipBestTool(worker, st, id);
  b.total = breakTicks(id, st.held);
  b.progress++;
  faceBlock(worker, pos);
  effects(worker, pos, id, b.progress);
  st.status = `Kırıyor: ${id.replace("minecraft:", "")} ${b.progress}/${b.total}`;
  if (b.progress < b.total) return { done: false };

  breaking.delete(worker.id);
  const harvests = canHarvest(id, st.held);
  const expected = opts.drop ?? (harvests ? dropFor(id) : "minecraft:air");
  const naturalWorked = naturalBreak(dim, pos);
  if (!harvests && naturalWorked) {
    // oyun komutu drop üretti ama harvest kuralı vermiyor olmalıydı; sim
    // farkını kabulleniyoruz — drop yerde kalır, pickup hedeflemez.
  }
  if (!naturalWorked && expected !== "minecraft:air") spawnItemAt(dim, expected, pos, 1);
  if (expected !== "minecraft:air") startPickup(st, pos, expected);
  const skill = opts.skill ?? "mining";
  if (st.skills[skill] !== undefined) st.skills[skill]++;
  st.dirty = true;
  return { done: true, broke: true, noDrop: expected === "minecraft:air" };
}
