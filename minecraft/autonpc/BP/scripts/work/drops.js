/**
 * AutoNPC v4.0 — doğal drop → iteme yürü → topla zinciri.
 * pickup koşu-zamanı durumu RAM'de (drop entity'leri zaten geçici).
 */
import { DROP_WAIT_TICKS, PICKUP_RADIUS, PICKUP_SEARCH_RADIUS } from "../core/config.js";
import { addInv } from "../core/state.js";
import { isToolItem } from "../core/registry.js";
import { itemStackOf, spawnItemAt } from "../sys/blocks.js";
import { walkTo } from "../nav/locomotion.js";
import { equipMainhand } from "../sys/equipment.js";
import { dist, horizDist, floorV } from "../core/math.js";

const pickups = new Map(); // workerId -> {origin, expect, wait, fallbackDone}

export function clearPickup(workerId) { pickups.delete(workerId); }
export function hasPickup(workerId) { return pickups.has(workerId); }

export function startPickup(st, origin, expect, amount = 1) {
  if (!expect || expect === "minecraft:air") return;
  // workerId'yi state üzerinden bilmiyoruz; çağıran tick'te runPickup worker ile eşler.
  st._pendingPickup = { origin: floorV(origin), expect, amount };
  st.dirty = true;
}

function nearestDrop(worker, p) {
  try {
    const ents = worker.dimension.getEntities({
      type: "minecraft:item",
      location: { x: p.origin.x + 0.5, y: p.origin.y + 0.5, z: p.origin.z + 0.5 },
      maxDistance: PICKUP_SEARCH_RADIUS,
    });
    let best, bd = Infinity;
    for (const e of ents) {
      const s = itemStackOf(e);
      if (s && p.expect && s.typeId !== p.expect) continue;
      const d = dist(e.location, p.origin);
      if (d < bd) { best = e; bd = d; }
    }
    return best;
  } catch (e) { return undefined; }
}

/** Her tick, görev koşturulmadan ÖNCE çağrılır. true = bu tick pickup'a harcandı. */
export function runPickup(worker, st) {
  // state'ten bekleyen pickup'ı devral (persist üzerinden de gelebilir)
  if (st._pendingPickup) {
    pickups.set(worker.id, { ...st._pendingPickup, wait: DROP_WAIT_TICKS, fallbackDone: false });
    delete st._pendingPickup;
    st.dirty = true;
  }
  const p = pickups.get(worker.id);
  if (!p) return false;

  const item = nearestDrop(worker, p);
  if (!item) {
    if (p.wait-- > 0) { st.status = `Drop bekleniyor: ${p.expect.replace("minecraft:", "")}`; return true; }
    if (!p.fallbackDone) {
      // bazı sürümlerde komut drop'u üretmeyebilir; itemi YERE bırak (envantere yazma yok)
      spawnItemAt(worker.dimension, p.expect, p.origin, p.amount);
      p.fallbackDone = true;
      p.wait = 10;
      st.status = "Drop görünmedi; item yere bırakıldı";
      return true;
    }
    pickups.delete(worker.id);
    st.status = "Item bulunamadı; görev sürüyor";
    return false;
  }

  const t = item.location;
  if (horizDist(worker.location, t) > PICKUP_RADIUS) {
    st.status = "Yerdeki iteme yürüyor";
    const r = walkTo(worker, floorV(t), { reach: 0, arrive: PICKUP_RADIUS, speed: 0.18 });
    if (r.blocked) { pickups.delete(worker.id); return false; }
    return true;
  }
  const stack = itemStackOf(item) || { typeId: p.expect, amount: p.amount };
  try { item.remove(); } catch (e) { /* başka şey kapmış olabilir */ }
  addInv(st, stack.typeId, stack.amount || 1);
  if (!isToolItem(st.held)) equipMainhand(worker, st, stack.typeId);
  pickups.delete(worker.id);
  st.status = `Aldı: ${stack.typeId.replace("minecraft:", "")} x${stack.amount || 1}`;
  return true;
}
