/**
 * AutoNPC v4.0 — WorkerState: tek doğruluk kaynağı + kalıcılık entegrasyonu.
 * D1 düzeltmesi: her mutasyon `dirty` işaretler; sys/tick periyodik olarak
 * core/persist.js ile entity dynamic property'ye yazar.
 */
import { VERSION } from "./config.js";
import { floorV, keyV } from "./math.js";
import { trace } from "./log.js";
import { BLACKLIST_TICKS } from "./config.js";

const states = new Map(); // entityId -> WorkerState (canlı önbellek)

export function createDefaultState(worker, ownerName = "") {
  return {
    schema: 4,
    version: VERSION,
    owner: ownerName,
    base: worker ? floorV(worker.location) : { x: 0, y: 0, z: 0 },
    status: "Emir bekliyor",
    task: undefined,           // { type, data }
    taskQueue: [],
    inventory: {},             // itemId -> adet (sanal envanter)
    skills: { mining: 0, woodcutting: 0, building: 0, crafting: 0 },
    auto: false,
    held: "minecraft:air",
    blacklist: {},             // "x,y,z" -> kalan tick
    obstacleAttempts: {},      // "x,y,z" -> deneme sayısı
    trace: [],
    dirty: true,
  };
}

export function cacheState(workerId, st) { states.set(workerId, st); }
export function cachedState(workerId) { return states.get(workerId); }
export function dropCachedState(workerId) { states.delete(workerId); }

function mark(st) { st.dirty = true; }

// ---- görev yaşam döngüsü ----
export function setTask(st, type, data = {}) {
  st.task = { type, data };
  st.status = `Görev: ${type}`;
  trace(st, `task:${type}`);
  mark(st);
}
export function queueTask(st, type, data = {}) {
  st.taskQueue.push({ type, data });
  if (!st.task) nextTask(st);
  mark(st);
}
/** Mevcut görevi koruyarak öne alt-görev sokar (D7: tek implementasyon). */
export function pushSubTask(st, type, data = {}) {
  if (st.task) st.taskQueue.unshift(st.task);
  st.task = { type, data };
  st.status = `Alt görev: ${type}`;
  trace(st, `sub:${type}`);
  mark(st);
}
export function nextTask(st) {
  st.task = st.taskQueue.shift();
  st.status = st.task ? `Görev: ${st.task.type}` : (st.auto ? "Otomatik mod" : "Emir bekliyor");
  mark(st);
}
export function finishTask(st, msg = "Tamamlandı") {
  nextTask(st);
  if (!st.task) st.status = msg;
  trace(st, `done:${msg.slice(0, 24)}`);
  mark(st);
}
export function stopAll(st) {
  st.task = undefined;
  st.taskQueue = [];
  st.auto = false;
  st.status = "Durduruldu";
  mark(st);
}

// ---- envanter ----
export function addInv(st, item, amount = 1) {
  if (!item || item === "minecraft:air" || amount <= 0) return;
  st.inventory[item] = (st.inventory[item] ?? 0) + amount;
  trace(st, `+${item.replace("minecraft:", "")}x${amount}`);
  mark(st);
}
export function removeInv(st, item, amount = 1) {
  const have = st.inventory[item] ?? 0;
  const take = Math.min(have, amount);
  if (take <= 0) return 0;
  st.inventory[item] = have - take;
  if (st.inventory[item] <= 0) delete st.inventory[item];
  trace(st, `-${item.replace("minecraft:", "")}x${take}`);
  mark(st);
  return take;
}
export function countInv(st, item) { return st.inventory[item] ?? 0; }
export function countAny(st, items) { return items.reduce((n, id) => n + countInv(st, id), 0); }
export function invText(st, limit = 24) {
  const e = Object.entries(st.inventory).filter(([, n]) => n > 0).slice(0, limit);
  return e.length ? e.map(([k, v]) => `${k.replace("minecraft:", "")} x${v}`).join("\n") : "boş";
}
export function setHeld(st, item) {
  st.held = item || "minecraft:air";
  mark(st);
}

// ---- hedef kara listesi ----
export function blacklistPos(st, pos, ticks = BLACKLIST_TICKS) {
  st.blacklist[keyV(pos)] = ticks;
  trace(st, `bl:${keyV(pos)}`);
  mark(st);
}
export function isBlacklisted(st, pos) { return (st.blacklist[keyV(pos)] ?? 0) > 0; }
export function tickBlacklist(st) {
  for (const k of Object.keys(st.blacklist)) {
    if (--st.blacklist[k] <= 0) delete st.blacklist[k];
  }
}
