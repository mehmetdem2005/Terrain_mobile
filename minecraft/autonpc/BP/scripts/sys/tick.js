/**
 * AutoNPC v4.0 — ana döngü.
 * Worker başına: blacklist yaşlandır → pickup zinciri → görev işle → isim/persist.
 * Hata izolasyonu: bir worker'ın istisnası diğerlerini durdurmaz.
 */
import { system } from "@minecraft/server";
import { TICK_INTERVAL, PERSIST_EVERY } from "../core/config.js";
import { allWorkers, updateName } from "./workers.js";
import { loadState, saveState } from "../core/persist.js";
import { tickBlacklist, setTask, nextTask } from "../core/state.js";
import { runPickup } from "../work/drops.js";
import { JOBS } from "../jobs/index.js";
import { countInv, countAny } from "../core/state.js";
import { LOG_BLOCKS } from "../core/registry.js";
import { trace } from "../core/log.js";

function chooseAutoTask(st) {
  if (countAny(st, [...LOG_BLOCKS]) + countInv(st, "minecraft:oak_planks") < 8) {
    return setTask(st, "gather_wood", { tree: "any", amount: 16, auto: true });
  }
  if (countInv(st, "minecraft:cobblestone") < 8) {
    return setTask(st, "collect_block", { blockId: "minecraft:stone", amount: 8, auto: true });
  }
  return setTask(st, "mine_ore", { group: "iron", amount: 8, auto: true });
}

let counter = 0;

export function startTick() {
  system.runInterval(() => {
    counter++;
    for (const w of allWorkers()) {
      let st;
      try {
        st = loadState(w);
        tickBlacklist(st);
        if (!runPickup(w, st)) {
          if (!st.task && st.auto) chooseAutoTask(st);
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
