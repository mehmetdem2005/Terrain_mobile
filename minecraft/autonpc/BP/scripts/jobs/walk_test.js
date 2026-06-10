/** AutoNPC v4.0 — navigasyon testi görevi. */
import { finishTask, blacklistPos } from "../core/state.js";
import { walkTo } from "../nav/locomotion.js";

export function tickWalkTest(worker, st, data) {
  const target = data.target || st.base;
  st.status = "Yürüme testi (A*)";
  const r = walkTo(worker, { x: Math.floor(target.x), y: Math.floor(target.y), z: Math.floor(target.z) }, { reach: 1 });
  if (r.reached) return finishTask(st, "Yürüme testi tamamlandı");
  if (r.blocked) { blacklistPos(st, target); return finishTask(st, "Hedefe yol bulunamadı"); }
}
