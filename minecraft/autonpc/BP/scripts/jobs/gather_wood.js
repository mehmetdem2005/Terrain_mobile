/**
 * AutoNPC v4.0 — ağaç kesme görevi.
 * Akış: tohum log tara → bağlı log kümesini planla → alttan üste kır →
 * (istenirse) yaprak/elma aşaması.
 */
import { TREE_TYPES, APPLE_LEAVES, LEAF_BLOCKS } from "../core/registry.js";
import { TREE_SCAN_RADIUS } from "../core/config.js";
import { blockIdAt } from "../sys/blocks.js";
import { scanStep, resetScan } from "../work/scanner.js";
import { countAny, countInv, finishTask, isBlacklisted, blacklistPos } from "../core/state.js";
import { approachAndBreak } from "./job.js";
import { horizDist, keyV } from "../core/math.js";
import { dropFor } from "../core/registry.js";

function connectedLogs(dim, seed, logSet, fromLoc) {
  const start = { x: Math.floor(seed.x), y: Math.floor(seed.y), z: Math.floor(seed.z) };
  const stack = [start], seen = new Set(), out = [];
  while (stack.length && out.length < 128) {
    const p = stack.pop();
    const k = keyV(p);
    if (seen.has(k)) continue;
    seen.add(k);
    if (!logSet.has(blockIdAt(dim, p))) continue;
    out.push(p);
    for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) for (let dz = -1; dz <= 1; dz++) {
      if (dx || dy || dz) stack.push({ x: p.x + dx, y: p.y + dy, z: p.z + dz });
    }
  }
  out.sort((a, b) => a.y - b.y || horizDist(fromLoc, a) - horizDist(fromLoc, b));
  return out;
}

export function tickGatherWood(worker, st, data) {
  const tree = TREE_TYPES[data.tree || "any"] || TREE_TYPES.any;
  const logSet = new Set(tree.logs);
  const amount = data.amount ?? 32;
  if (countAny(st, tree.logs) >= amount) {
    resetScan(worker.id, "wood");
    return finishTask(st, `Odun tamam x${countAny(st, tree.logs)}`);
  }

  // plan yoksa tohum ara
  if (!data.plan || !data.plan.length) {
    const r = scanStep(worker, "wood", TREE_SCAN_RADIUS,
      (id, pos) => logSet.has(id) && !isBlacklisted(st, pos));
    if (r.scanning) { st.status = `${tree.label} aranıyor`; return; }
    if (r.exhausted || !r.found) { st.status = `${tree.label} bulunamadı (yarıçap ${TREE_SCAN_RADIUS})`; return; }
    data.plan = connectedLogs(worker.dimension, r.found, logSet, worker.location);
    data.treeCenter = { ...r.found };
    st.status = `Ağaç planlandı: ${data.plan.length} log`;
    st.dirty = true;
    return;
  }

  // plandaki ilk canlı hedef
  while (data.plan.length && !logSet.has(blockIdAt(worker.dimension, data.plan[0]))) data.plan.shift();
  if (!data.plan.length) {
    const center = data.treeCenter;
    data.plan = undefined;
    if (data.apples && center) {
      st.taskQueue.unshift({ type: "collect_leaves", data: { center, leaves: tree.leaves, amount: 24, appleAmount: 1 } });
      return finishTask(st, "Gövde bitti; yaprak aşaması");
    }
    st.status = "Ağaç bitti; yenisi aranacak";
    st.dirty = true;
    return;
  }

  const target = data.plan[0];
  const id = blockIdAt(worker.dimension, target);
  const r = approachAndBreak(worker, st, target, { drop: dropFor(id), skill: "woodcutting" }, tree.label);
  if (r.broke || r.failed) data.plan.shift();
  if (r.failed) blacklistPos(st, target);
}

export function tickCollectLeaves(worker, st, data) {
  const leaves = new Set(data.leaves || [...LEAF_BLOCKS]);
  const amount = data.amount ?? 16;
  data.done = data.done ?? 0;
  if (data.done >= amount || countInv(st, "minecraft:apple") >= (data.appleAmount ?? 999)) {
    resetScan(worker.id, "leaves");
    return finishTask(st, "Yaprak/elma tamam");
  }
  let target = data.target;
  if (!target || !leaves.has(blockIdAt(worker.dimension, target)) || isBlacklisted(st, target)) {
    const r = scanStep(worker, "leaves", 8, (id, pos) => leaves.has(id) && !isBlacklisted(st, pos));
    if (r.scanning) { st.status = "Yaprak aranıyor"; return; }
    if (!r.found) return finishTask(st, "Yakında yaprak yok");
    target = data.target = r.found;
    st.dirty = true;
  }
  const id = blockIdAt(worker.dimension, target);
  const drop = APPLE_LEAVES.has(id) && Math.random() < 0.18 ? "minecraft:apple" : "minecraft:air";
  const r = approachAndBreak(worker, st, target, { drop, skill: "woodcutting" }, "Yaprak");
  if (r.broke) { data.done++; data.target = undefined; st.dirty = true; }
  if (r.failed) data.target = undefined;
}
