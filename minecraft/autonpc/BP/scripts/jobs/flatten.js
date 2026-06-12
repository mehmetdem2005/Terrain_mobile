/**
 * AutoNPC v5.0 — seçili alanı düzleştir + çukur doldur.
 * Seviye = seçimin alt y'si. Üstündeki bloklar GERÇEK kırılır (drop'lu),
 * altındaki hava cepleri (creeper çukurları) envanter toprağıyla doldurulur.
 */
import { finishTask, countInv, removeInv, pushSubTask, blacklistPos, isBlacklisted } from "../core/state.js";
import { blockIdAt, setBlock, playSoundAt } from "../sys/blocks.js";
import { isAir, isBreakable, isLiquid } from "../core/registry.js";
import { approachAndBreak, canInteract } from "./job.js";
import { walkTo } from "../nav/locomotion.js";

const FILL_ITEMS = ["minecraft:dirt", "minecraft:cobblestone", "minecraft:netherrack", "minecraft:sand"];
const FILL_DEPTH = 4;

function nextOp(worker, st, data) {
  const { min, max } = data.region;
  const level = data.level ?? min.y;
  for (let x = min.x; x <= max.x; x++) {
    for (let z = min.z; z <= max.z; z++) {
      // 1) seviye üstünü kaz (üstten alta)
      for (let y = Math.max(max.y, level + 1); y >= level; y--) {
        const pos = { x, y, z };
        const id = blockIdAt(worker.dimension, pos);
        if (!isAir(id) && isBreakable(id) && !isBlacklisted(st, pos)) return { type: "break", pos, id };
      }
      // 2) seviye altındaki boşlukları doldur
      for (let y = level - 1; y >= level - FILL_DEPTH; y--) {
        const pos = { x, y, z };
        const id = blockIdAt(worker.dimension, pos);
        if (isAir(id) || isLiquid(id)) return { type: "fill", pos };
      }
    }
  }
  return undefined;
}

export function tickFlatten(worker, st, data) {
  if (!data.region) return finishTask(st, "Seçim yok: çubukla 2 köşe işaretle");
  const op = nextOp(worker, st, data);
  if (!op) return finishTask(st, "Alan düzleştirildi ve çukurlar dolduruldu");

  if (op.type === "break") {
    const r = approachAndBreak(worker, st, op.pos, { skill: "building" }, "Düzleştirme");
    if (r.failed) blacklistPos(st, op.pos);
    return;
  }
  // fill
  const filler = FILL_ITEMS.find((id) => countInv(st, id) > 0);
  if (!filler) return pushSubTask(st, "collect_block", { blockId: "minecraft:dirt", amount: 16, reason: "dolgu" });
  if (!canInteract(worker, op.pos, 4.5, 5)) {
    st.status = "Dolgu noktasına yürüyor";
    const w = walkTo(worker, op.pos, { reach: 2 });
    if (w.blocked) blacklistPos(st, op.pos);
    return;
  }
  removeInv(st, filler, 1);
  setBlock(worker.dimension, op.pos, filler);
  playSoundAt(worker.dimension, "dig.gravel", op.pos);
  try { worker.playAnimation("animation.autonpc.worker.swing"); } catch (e) { /* opsiyonel */ }
  st.skills.building++;
  st.status = `Çukur dolduruyor (${filler.replace("minecraft:", "")})`;
  st.dirty = true;
}
