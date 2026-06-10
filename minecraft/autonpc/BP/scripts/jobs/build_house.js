/**
 * AutoNPC v4.0 — ev inşaatı. (D10 düzeltmesi)
 * v3 setType ile uzaktan blok basıyordu. v4: her blok için malzeme düşülür,
 * bloğun yanına YÜRÜNÜR, yerleştirme sesi/animasyonuyla konur (RealWork).
 */
import { countInv, removeInv, finishTask, pushSubTask } from "../core/state.js";
import { craftPlanks } from "../work/tools.js";
import { blockIdAt, setBlock, playSoundAt } from "../sys/blocks.js";
import { isAir, LOG_BLOCKS } from "../core/registry.js";
import { walkTo, faceBlock } from "../nav/locomotion.js";
import { horizDist } from "../core/math.js";

const NEED_WOOD = 28;
const NEED_STONE = 18;
const PLACE_RANGE = 4.0;

function totalWood(st) {
  return [...LOG_BLOCKS].reduce((n, id) => n + countInv(st, id), 0) + countInv(st, "minecraft:oak_planks");
}

/** 5x5 taban, 3 duvar katı (taş), plank çatı + zemin. */
function housePlan(base) {
  const out = [];
  for (let x = -2; x <= 2; x++) for (let z = -2; z <= 2; z++) out.push([base.x + x, base.y, base.z + z, "minecraft:oak_planks"]);
  for (let y = 1; y <= 3; y++) {
    for (let x = -2; x <= 2; x++) for (let z = -2; z <= 2; z++) {
      if (Math.abs(x) !== 2 && Math.abs(z) !== 2) continue;
      // kapı boşluğu: -Z cephesi ortası, y1-y2
      if (z === -2 && x === 0 && y <= 2) continue;
      out.push([base.x + x, base.y + y, base.z + z, y === 3 ? "minecraft:oak_planks" : "minecraft:cobblestone"]);
    }
  }
  for (let x = -2; x <= 2; x++) for (let z = -2; z <= 2; z++) out.push([base.x + x, base.y + 4, base.z + z, "minecraft:oak_planks"]);
  return out;
}

export function tickBuildHouse(worker, st, data) {
  if (totalWood(st) < NEED_WOOD) return pushSubTask(st, "gather_wood", { tree: "any", amount: NEED_WOOD, reason: "house" });
  if (countInv(st, "minecraft:cobblestone") < NEED_STONE) {
    return pushSubTask(st, "collect_block", { blockId: "minecraft:stone", amount: NEED_STONE, reason: "house" });
  }
  craftPlanks(st, NEED_WOOD);

  if (!data.plan) {
    data.plan = housePlan(st.base);
    data.index = 0;
    st.dirty = true;
  }
  while (data.index < data.plan.length) {
    const [x, y, z, id] = data.plan[data.index];
    const cur = blockIdAt(worker.dimension, { x, y, z });
    if (!isAir(cur) || countInv(st, id) <= 0 && id !== "minecraft:oak_planks") {
      // dolu hücre veya malzemesiz blok: atla (plank için craft yukarıda garanti)
      if (!isAir(cur)) { data.index++; continue; }
    }
    // bloğa yaklaş (RealWork: uzaktan basmak yok)
    if (horizDist(worker.location, { x: x + 0.5, z: z + 0.5 }) > PLACE_RANGE) {
      st.status = `Ev: bloğa yürüyor ${data.index}/${data.plan.length}`;
      const r = walkTo(worker, { x, y, z }, { reach: 2 });
      if (r.blocked) { data.index++; st.dirty = true; }
      return;
    }
    if (removeInv(st, id, 1) <= 0) { data.index++; continue; }
    faceBlock(worker, { x, y, z });
    setBlock(worker.dimension, { x, y, z }, id);
    playSoundAt(worker.dimension, id.includes("plank") ? "dig.wood" : "dig.stone", { x, y, z });
    try { worker.playAnimation("animation.autonpc.worker.swing"); } catch (e) { /* opsiyonel */ }
    st.skills.building++;
    st.status = `Ev yapıyor ${data.index + 1}/${data.plan.length}`;
    data.index++;
    st.dirty = true;
    return; // tick başına bir blok
  }
  finishTask(st, "Ev tamamlandı");
}
