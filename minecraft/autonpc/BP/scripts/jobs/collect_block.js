/**
 * AutoNPC v4.0 — tek blok türü toplama görevi.
 */
import { SCAN_RADIUS } from "../core/config.js";
import { dropFor, isBreakable } from "../core/registry.js";
import { blockIdAt } from "../sys/blocks.js";
import { scanStep, resetScan } from "../work/scanner.js";
import { countInv, finishTask, isBlacklisted } from "../core/state.js";
import { ensureToolFor } from "../work/tools.js";
import { approachAndBreak } from "./job.js";

export function canonicalBlockId(raw) {
  let id = String(raw || "").trim().toLowerCase().replace(/ /g, "_");
  if (!id) return "";
  if (!id.includes(":")) id = `minecraft:${id}`;
  return id;
}

export function tickCollectBlock(worker, st, data) {
  const blockId = canonicalBlockId(data.blockId || "minecraft:stone");
  const amount = data.amount ?? 32;
  const drop = dropFor(blockId);
  if (countInv(st, drop) >= amount) {
    resetScan(worker.id, "collect");
    return finishTask(st, `${blockId.replace("minecraft:", "")} tamam x${amount}`);
  }
  if (!isBreakable(blockId)) return finishTask(st, `Toplanamaz blok: ${blockId}`);
  if (!ensureToolFor(st, blockId)) return; // alt-görev itildi

  let target = data.target;
  if (!target || blockIdAt(worker.dimension, target) !== blockId || isBlacklisted(st, target)) {
    const r = scanStep(worker, "collect", SCAN_RADIUS, (id, pos) => id === blockId && !isBlacklisted(st, pos));
    if (r.scanning) { st.status = `${blockId.replace("minecraft:", "")} aranıyor`; return; }
    if (!r.found) { st.status = `${blockId.replace("minecraft:", "")} bulunamadı`; return; }
    target = data.target = r.found;
    st.dirty = true;
  }
  const r = approachAndBreak(worker, st, target, { drop, skill: "mining" }, blockId.replace("minecraft:", ""));
  if (r.broke || r.failed) { data.target = undefined; st.dirty = true; }
}
