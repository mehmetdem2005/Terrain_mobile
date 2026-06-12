/**
 * AutoNPC v5.2 — KURTARMA görevi: imdat çağrısına git, mahsur arkadaşın
 * etrafını kaz (3 yükseklik, 4 yön), çağrıyı kapat, işine dön.
 */
import { finishTask } from "../core/state.js";
import { walkTo } from "../nav/locomotion.js";
import { breakStep } from "../work/breaker.js";
import { blockIdAt } from "../sys/blocks.js";
import { isSolid, isBreakable } from "../core/registry.js";
import { cancelHelp, callFor } from "../sys/coop.js";
import { angry } from "../chat/personality.js";
import { dist } from "../core/math.js";

export function tickRescue(worker, st, data) {
  const call = callFor(data.stuckId);
  if (!call) return finishTask(st, "Çağrı kapandı; işe dönülüyor");
  const p = call.pos;

  if (dist(worker.location, { x: p.x + 0.5, y: p.y, z: p.z + 0.5 }) > 3.2) {
    st.status = `Kurtarmaya gidiyor (${call.reason})`;
    const r = walkTo(worker, p, { reach: 2 });
    if (r.blocked) return finishTask(st, "Kurtarma yoluna ulaşamadı");
    return;
  }
  // mahsurun etrafını aç: 4 yön × ayak/kafa
  for (const [dx, dz] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
    for (const dy of [0, 1]) {
      const c = { x: p.x + dx, y: p.y + dy, z: p.z + dz };
      const id = blockIdAt(worker.dimension, c);
      if (isSolid(id) && isBreakable(id)) {
        st.status = "Kurtarıyor: etrafını kazıyor";
        breakStep(worker, st, c, { skill: "mining" });
        return;
      }
    }
  }
  cancelHelp(data.stuckId);
  angry(st, "rescue_done");
  finishTask(st, "Kurtarma tamamlandı");
}
