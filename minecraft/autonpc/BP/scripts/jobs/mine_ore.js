/**
 * AutoNPC v4.0 — maden görevi: cevher tara; görünmüyorsa merdiven tüneli aç.
 * Tünel yönü v3'teki sabit +X yerine NPC'nin o anki bakış yönünden alınır.
 */
import { ORES, dropFor, isAir } from "../core/registry.js";
import { ORE_SCAN_RADIUS } from "../core/config.js";
import { blockIdAt } from "../sys/blocks.js";
import { scanStep, resetScan } from "../work/scanner.js";
import { countInv, finishTask, isBlacklisted } from "../core/state.js";
import { ensureToolFor } from "../work/tools.js";
import { approachAndBreak } from "./job.js";

function tunnelDir(worker, data) {
  if (data.dir) return data.dir;
  try {
    const v = worker.getViewDirection();
    data.dir = Math.abs(v.x) >= Math.abs(v.z)
      ? { x: Math.sign(v.x) || 1, z: 0 }
      : { x: 0, z: Math.sign(v.z) || 1 };
  } catch (e) { data.dir = { x: 1, z: 0 }; }
  return data.dir;
}

function nextStairBlock(worker, data) {
  if (!data.stairBase) {
    const l = worker.location;
    data.stairBase = { x: Math.floor(l.x), y: Math.floor(l.y), z: Math.floor(l.z) };
    data.stairIndex = 1;
    data.stairPhase = 0;
  }
  const dir = tunnelDir(worker, data);
  const i = data.stairIndex;
  const x = data.stairBase.x + dir.x * i;
  const z = data.stairBase.z + dir.z * i;
  const y = data.stairBase.y - Math.floor(i / 2);
  return data.stairPhase === 0 ? { x, y, z } : { x, y: y + 1, z };
}
function advanceStair(data) {
  data.stairPhase = (data.stairPhase ?? 0) + 1;
  if (data.stairPhase > 1) { data.stairPhase = 0; data.stairIndex = (data.stairIndex ?? 1) + 1; }
}

export function tickMineOre(worker, st, data) {
  const ore = ORES[data.group || "iron"] || ORES.iron;
  const oreSet = new Set(ore.ores);
  const amount = data.amount ?? 8;
  if (countInv(st, ore.drop) >= amount) {
    resetScan(worker.id, "ore");
    return finishTask(st, `${ore.label} tamam x${amount}`);
  }
  if (!ensureToolFor(st, ore.ores[0])) return; // alt-görev itildi

  // hedef cevher
  let target = data.target;
  if (target && (!oreSet.has(blockIdAt(worker.dimension, target)) || isBlacklisted(st, target))) {
    target = data.target = undefined;
  }
  if (!target) {
    const r = scanStep(worker, "ore", ORE_SCAN_RADIUS, (id, pos) => oreSet.has(id) && !isBlacklisted(st, pos));
    if (r.scanning) { st.status = `${ore.label} aranıyor`; return; }
    if (r.found) { target = data.target = r.found; st.dirty = true; }
  }
  if (target) {
    const r = approachAndBreak(worker, st, target, { drop: ore.drop, skill: "mining" }, ore.label);
    if (r.broke || r.failed) { data.target = undefined; st.dirty = true; }
    return;
  }

  // cevher yok → merdiven tüneli
  const stair = nextStairBlock(worker, data);
  const id = blockIdAt(worker.dimension, stair);
  if (isAir(id)) { advanceStair(data); st.status = `${ore.label}: tünel ilerliyor`; st.dirty = true; return; }
  if (!ensureToolFor(st, id)) return;
  const r = approachAndBreak(worker, st, stair, { drop: dropFor(id), skill: "mining" }, `${ore.label} tüneli`);
  if (r.broke || r.gone) { advanceStair(data); st.dirty = true; }
  if (r.failed) { data.stairBase = undefined; data.dir = undefined; }
}
