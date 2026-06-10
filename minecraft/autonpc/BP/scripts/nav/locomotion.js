/**
 * AutoNPC v4.0 — yol takipçisi. (D3 düzeltmesi)
 * A* yolunu nokta-nokta, sabit hızda, yüze dönerek izler. Fizik hack'i yok:
 * deterministik teleport adımı = takılma yok; sapma/stuck'ta re-plan ister.
 *
 * Worker-başına koşu-zamanı durumu burada (persist edilmez; yol her zaman
 * yeniden hesaplanabilir).
 */
import { findPath } from "./astar.js";
import { WALK_SPEED, ARRIVE_DIST, STUCK_LIMIT, REPLAN_COOLDOWN } from "../core/config.js";
import { horizDist, yawToward, keyV } from "../core/math.js";

const navs = new Map(); // workerId -> {path, idx, targetKey, stuck, lastPos, cooldown}

export function clearNav(workerId) { navs.delete(workerId); }

function planFor(worker, nav, target, reach) {
  const r = findPath(worker.dimension, worker.location, target, reach);
  nav.cooldown = REPLAN_COOLDOWN;
  if (!r || !r.path.length) { nav.path = undefined; return false; }
  nav.path = r.path;
  nav.idx = 0;
  nav.complete = r.complete;
  return true;
}

/**
 * Her tick çağrılır. @returns {reached, moving, blocked}
 * blocked: plan bulunamadı (çağıran kara listeye alıp başka hedef seçmeli).
 */
export function walkTo(worker, target, opts = {}) {
  const reach = opts.reach ?? 1;
  let nav = navs.get(worker.id);
  const tKey = keyV(target);

  // varış kontrolü (yol durumundan bağımsız)
  if (horizDist(worker.location, { x: target.x + 0.5, z: target.z + 0.5 }) <= (opts.arrive ?? 1.25)
      && Math.abs(target.y - worker.location.y) <= 2.2) {
    clearNav(worker.id);
    return { reached: true };
  }

  if (!nav || nav.targetKey !== tKey) {
    nav = { targetKey: tKey, stuck: 0, cooldown: 0, lastPos: undefined };
    navs.set(worker.id, nav);
  }
  if (nav.cooldown > 0) nav.cooldown--;

  if (!nav.path || nav.idx >= nav.path.length) {
    if (nav.path && nav.complete === false && nav.idx >= nav.path.length) {
      // kısmi yol bitti: hedefe devam planı
      nav.path = undefined;
    }
    if (nav.cooldown > 0 && nav.path === undefined && nav.failedOnce) return { moving: false };
    if (!planFor(worker, nav, target, reach)) {
      nav.failedOnce = true;
      return { blocked: true };
    }
    nav.failedOnce = false;
  }

  const wp = nav.path[nav.idx];
  const wpC = { x: wp.x + 0.5, y: wp.y, z: wp.z + 0.5 };
  const loc = worker.location;
  const dx = wpC.x - loc.x, dz = wpC.z - loc.z;
  const dh = Math.sqrt(dx * dx + dz * dz);

  if (dh <= ARRIVE_DIST && Math.abs(wpC.y - loc.y) <= 1.5) {
    nav.idx++;
    nav.stuck = 0;
    return { moving: true };
  }

  const step = Math.min(opts.speed ?? WALK_SPEED, dh);
  const nx = loc.x + (dx / dh) * step;
  const nz = loc.z + (dz / dh) * step;
  // dikey: ara nokta seviyesine yumuşak yaklaş (basamak çıkışı/inişini oyun yerine biz yapıyoruz)
  let ny = loc.y;
  const dy = wpC.y - loc.y;
  if (Math.abs(dy) > 0.05) ny = loc.y + Math.sign(dy) * Math.min(0.25, Math.abs(dy));

  try {
    worker.teleport({ x: nx, y: ny, z: nz }, {
      dimension: worker.dimension,
      rotation: { x: 0, y: yawToward(dx, dz) },
    });
  } catch (e) { /* entity geçersiz */ }
  try { worker.playAnimation(`animation.autonpc.worker.walk`); } catch (e) { /* anim opsiyonel */ }

  // ilerleme kontrolü
  if (nav.lastPos && horizDist(loc, nav.lastPos) < 0.02) nav.stuck++; else nav.stuck = 0;
  nav.lastPos = { x: loc.x, y: loc.y, z: loc.z };
  if (nav.stuck > STUCK_LIMIT) {
    nav.path = undefined; // re-plan
    nav.stuck = 0;
    if (nav.cooldown > 0) return { blocked: true };
  }
  return { moving: true };
}

export function faceBlock(worker, pos) {
  const loc = worker.location;
  try {
    worker.teleport(loc, {
      dimension: worker.dimension,
      rotation: { x: 0, y: yawToward((pos.x + 0.5) - loc.x, (pos.z + 0.5) - loc.z) },
    });
  } catch (e) { /* yok sayılabilir */ }
}
