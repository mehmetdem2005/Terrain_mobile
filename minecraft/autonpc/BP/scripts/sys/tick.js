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
import { resetAllScans } from "../work/scanner.js";
import { clearNav } from "../nav/locomotion.js";
import { blockIdAt } from "./blocks.js";
import { isSolid } from "../core/registry.js";

let counter = 0;

// v5.0.2 WATCHDOG: görev var ama hiçbir şey değişmiyorsa NPC kendini kurtarır.
// imza = görev + durum + envanter toplamı + kaba konum; NUDGE_AT tick boyunca
// aynı kalırsa hedef/plan/tarama sıfırlanır (yeniden dener), ABORT_AT'ta görev
// düşürülür. "Takılıp kalma" sınıfının oyun-içi sigortası.
const NUDGE_AT = 400;
const ABORT_AT = 1200;
const wd = new Map(); // workerId -> {sig, ticks, nudged}

function watchdog(w, st) {
  if (!st.task) { wd.delete(w.id); return; }
  const inv = Object.values(st.inventory).reduce((a, b) => a + b, 0);
  const l = w.location;
  const sig = `${st.task.type}|${st.status}|${inv}|${Math.floor(l.x)},${Math.floor(l.y)},${Math.floor(l.z)}`;
  const e = wd.get(w.id);
  if (!e || e.sig !== sig) { wd.set(w.id, { sig, ticks: 0, nudged: false }); return; }
  e.ticks++;
  if (e.ticks === NUDGE_AT && !e.nudged) {
    e.nudged = true;
    const d = st.task.data ?? {};
    d.target = undefined; d.plan = undefined; d.spot = undefined; d.scanWait = 0;
    resetAllScans(w.id);
    clearNav(w.id);
    // GÖMÜLME kurtarması: ayak hücresi katıysa yukarıdaki ilk boşluğa çık
    try {
      const fx = Math.floor(l.x), fy = Math.floor(l.y), fz = Math.floor(l.z);
      if (isSolid(blockIdAt(w.dimension, { x: fx, y: fy, z: fz }))) {
        for (let dy = 1; dy <= 4; dy++) {
          if (!isSolid(blockIdAt(w.dimension, { x: fx, y: fy + dy, z: fz }))
            && !isSolid(blockIdAt(w.dimension, { x: fx, y: fy + dy + 1, z: fz }))) {
            w.teleport({ x: fx + 0.5, y: fy + dy, z: fz + 0.5 }, { dimension: w.dimension });
            trace(st, "watchdog:unstuck");
            break;
          }
        }
      }
    } catch (err) { /* kurtarma opsiyonel */ }
    trace(st, "watchdog:nudge");
    st.status = `${st.status} [yeniden deneniyor]`;
    st.dirty = true;
  } else if (e.ticks >= ABORT_AT) {
    trace(st, `watchdog:abort:${st.task.type}`);
    nextTask(st);
    st.status = "Görev takıldı, watchdog düşürdü → sıradaki";
    st.dirty = true;
    wd.delete(w.id);
  }
}

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
        watchdog(w, st);
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
