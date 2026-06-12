/**
 * AutoNPC v5.0 — hazine avı: yüklü chunk'larda sandık bul, GERÇEK container
 * API'siyle yağmala, base'e dön. (/locate çıktısı Script API'ye kapalı —
 * kapsam: yakın sandıklar; PLAN_V5 dürüst sınırlar.)
 */
import { finishTask, addInv } from "../core/state.js";
import { scanStep, resetScan } from "../work/scanner.js";
import { blockAt } from "../sys/blocks.js";
import { walkTo } from "../nav/locomotion.js";
import { canInteract } from "./job.js";
import { keyV } from "../core/math.js";

const CHEST_IDS = new Set(["minecraft:chest", "minecraft:barrel", "minecraft:trapped_chest"]);

export function tickTreasure(worker, st, data) {
  data.looted = data.looted ?? [];

  if (data.returning) {
    st.status = "Ganimetle base'e dönüyor";
    const r = walkTo(worker, st.base, { reach: 2 });
    if (r.reached) return finishTask(st, `Hazine avı bitti: ${data.looted.length} sandık`);
    if (r.blocked) return finishTask(st, "Base'e yol yok; ganimet üstünde");
    return;
  }

  if (!data.target) {
    const r = scanStep(worker, "chest", 24, (id, pos) => CHEST_IDS.has(id) && !data.looted.includes(keyV(pos)));
    if (r.scanning) { st.status = "Sandık aranıyor"; return; }
    if (!r.found) {
      if (data.looted.length) { data.returning = true; return; }
      return finishTask(st, "Yakında sandık yok");
    }
    data.target = r.found;
    st.dirty = true;
  }

  const t = data.target;
  if (!canInteract(worker, t, 3.0, 3.5)) {
    st.status = "Sandığa yürüyor";
    const r = walkTo(worker, t, { reach: 1 });
    if (r.blocked) { data.looted.push(keyV(t)); data.target = undefined; }
    return;
  }
  // yağma: gerçek container içeriğini sanal envantere aktar
  try {
    const block = blockAt(worker.dimension, t);
    const cont = block?.getComponent("minecraft:inventory")?.container;
    if (cont) {
      let moved = 0;
      for (let i = 0; i < cont.size; i++) {
        const s = cont.getItem(i);
        if (!s) continue;
        addInv(st, s.typeId, s.amount);
        cont.setItem(i, undefined);
        moved += s.amount;
      }
      st.status = `Sandık yağmalandı: ${moved} eşya`;
    }
  } catch (e) { st.status = "Sandık açılamadı"; }
  data.looted.push(keyV(t));
  data.target = undefined;
  st.dirty = true;
}
