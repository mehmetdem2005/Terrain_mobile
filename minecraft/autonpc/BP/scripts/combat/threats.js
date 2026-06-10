/**
 * AutoNPC v5.0 — hayatta kalma refleksi (görevden ÖNCE her tick).
 * - hostil radar 14 blok
 * - creeper ≤4 blok: KALKAN penceresi aç (patlama hasarı events.js'te
 *   kalkan+zırh ile telafi edilir) ve geri çekil
 * - iskelet uzakta: yay; yakın hostil: kılıç kontra
 */
import { equipShield } from "./gear.js";
import { meleeAttack, bowAttack, canShoot, tickCooldown } from "./attack.js";
import { walkTo } from "../nav/locomotion.js";
import { dist, floorV } from "../core/math.js";

const HOSTILES = new Set([
  "minecraft:zombie", "minecraft:husk", "minecraft:drowned", "minecraft:skeleton",
  "minecraft:stray", "minecraft:creeper", "minecraft:spider", "minecraft:cave_spider",
  "minecraft:enderman", "minecraft:witch", "minecraft:pillager", "minecraft:vindicator",
  "minecraft:zombie_pigman", "minecraft:zombified_piglin", "minecraft:piglin", "minecraft:hoglin",
  "minecraft:wither_skeleton", "minecraft:blaze",
]);

export const shieldWindows = new Map(); // workerId -> kalan tick (events.js hasar telafisinde okur)

function nearestHostile(worker, radius) {
  let best, bd = radius;
  try {
    for (const e of worker.dimension.getEntities({ location: worker.location, maxDistance: radius })) {
      if (!HOSTILES.has(e.typeId)) continue;
      const d = dist(e.location, worker.location);
      if (d < bd) { best = e; bd = d; }
    }
  } catch (e) { /* boyut sınırı */ }
  return best;
}

/** @returns true → bu tick tehditle harcandı (görev koşmasın) */
export function threatTick(worker, st) {
  tickCooldown(worker.id);
  const w = shieldWindows.get(worker.id) ?? 0;
  if (w > 0) shieldWindows.set(worker.id, w - 1);
  else if (w === 0 && st.equipment?.offhand === "minecraft:shield") equipShield(worker, st, false);

  const hostile = nearestHostile(worker, 14);
  if (!hostile) return false;
  const d = dist(hostile.location, worker.location);

  if (hostile.typeId === "minecraft:creeper") {
    if (d <= 4.5) {
      // patlama an meselesi: kalkanı kaldır, yüzünü dön, geri adım
      equipShield(worker, st, true);
      shieldWindows.set(worker.id, 40);
      st.status = "Creeper! Kalkan kalktı, geri çekiliyor";
      const away = {
        x: Math.floor(worker.location.x + (worker.location.x - hostile.location.x) * 2),
        y: Math.floor(worker.location.y),
        z: Math.floor(worker.location.z + (worker.location.z - hostile.location.z) * 2),
      };
      walkTo(worker, away, { reach: 1, speed: 0.22 });
      return true;
    }
    if (d <= 9 && canShoot(st)) { st.status = "Creeper'a ok atıyor"; bowAttack(worker, st, hostile); return true; }
    return false;
  }

  if (d <= 3.2) { st.status = `Savaşıyor: ${hostile.typeId.replace("minecraft:", "")}`; meleeAttack(worker, st, hostile); return true; }
  if (d <= 12 && canShoot(st)) { st.status = `Ok atıyor: ${hostile.typeId.replace("minecraft:", "")}`; bowAttack(worker, st, hostile); return true; }
  if (d <= 6) {
    // silahsız ve yakın: hedefe yürü+kontra (kaçmak yerine; işçi 40 can)
    st.status = "Tehdide kontra yürüyor";
    walkTo(worker, floorV(hostile.location), { reach: 2 });
    return true;
  }
  return false;
}
