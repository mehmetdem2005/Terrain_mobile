/**
 * AutoNPC v4.0 — ana döngü.
 * Worker başına: blacklist yaşlandır → pickup zinciri → görev işle → isim/persist.
 * Hata izolasyonu: bir worker'ın istisnası diğerlerini durdurmaz.
 */
import { system } from "@minecraft/server";
import { TICK_INTERVAL, PERSIST_EVERY } from "../core/config.js";
import { allWorkers, updateName } from "./workers.js";
import { loadState, saveState } from "../core/persist.js";
import { tickBlacklist, nextTask } from "../core/state.js";
import { runPickup } from "../work/drops.js";
import { JOBS } from "../jobs/index.js";
import { trace } from "../core/log.js";
import { threatTick } from "../combat/threats.js";
import { directAuto } from "../auto/director.js";

let counter = 0;

export function startTick() {
  system.runInterval(() => {
    counter++;
    for (const w of allWorkers()) {
      let st;
      try {
        st = loadState(w);
        tickBlacklist(st);
        // v5: hayatta kalma refleksi her şeyden önce (creeper/kalkan/kontra)
        if (threatTick(w, st)) {
          if (counter % 10 === 0) updateName(w, st);
          continue;
        }
        if (!runPickup(w, st)) {
          if (!st.task && st.auto) directAuto(w, st);
          const t = st.task;
          if (t) {
            const job = JOBS[t.type];
            if (job) job(w, st, t.data ?? (t.data = {}));
            else { trace(st, `bilinmeyen:${t.type}`); nextTask(st); }
          }
        }
        if (counter % 10 === 0) updateName(w, st);
        if (counter % PERSIST_EVERY === 0) saveState(w, st);
      } catch (e) {
        try {
          if (st) { st.status = `Hata: ${String(e).slice(0, 50)}`; updateName(w, st); }
        } catch (e2) { /* raporlanamadı */ }
      }
    }
  }, TICK_INTERVAL);
}
