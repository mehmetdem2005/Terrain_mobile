/**
 * AutoNPC v4.0 — Job tabanı + ortak yardımcılar. (D7 düzeltmesi)
 * v3'te her job dosyası kendi pushSubTask/scanWait/yaklaş-kır kopyasını taşıyordu.
 * v4: tek yerde. Job'lar { tick(worker, st, data) } sözleşmesini uygular.
 */
import { INTERACT_RANGE, INTERACT_VERTICAL, OBSTACLE_MAX_PER_TARGET } from "../core/config.js";
import { isBreakable, isSolid, isPassable } from "../core/registry.js";
import { blockIdAt } from "../sys/blocks.js";
import { walkTo } from "../nav/locomotion.js";
import { breakStep } from "../work/breaker.js";
import { blacklistPos } from "../core/state.js";
import { horizDist, keyV } from "../core/math.js";

/** Bloğa etkileşim mesafesinde miyiz? */
export function canInteract(worker, pos, range = INTERACT_RANGE, vertical = INTERACT_VERTICAL) {
  return horizDist(worker.location, { x: pos.x + 0.5, z: pos.z + 0.5 }) <= range
    && Math.abs((pos.y + 0.5) - worker.location.y) <= vertical;
}

/** Hedefin yanındaki en uygun durulabilir hücre (A*'ın reach'i bunu çoğunlukla halleder;
 *  hedefin KENDİSİ katı blok olduğu için bitişiğine yürütürüz). */
export function adjacentGoal(pos) {
  return { x: pos.x, y: pos.y, z: pos.z }; // A* reach=1 ile bitişik hücrede durur
}

/**
 * Hedefe yaklaş; yol yoksa hedefe doğru gövde hizasındaki ilk kırılabilir bloğu kır (tünel).
 * @returns {near, working, failed}
 */
export function approachOrTunnel(worker, st, target, label) {
  if (canInteract(worker, target)) return { near: true };
  st.status = `${label}: hedefe yürüyor`;
  const r = walkTo(worker, adjacentGoal(target), { reach: 1 });
  if (r.reached || canInteract(worker, target)) return { near: true };
  if (!r.blocked) return { working: true };

  // yol yok → hedef yönünde tünel: yüz hizasında ilk katı kırılabilir blok
  const loc = worker.location;
  const dx = (target.x + 0.5) - loc.x, dz = (target.z + 0.5) - loc.z;
  const dh = Math.sqrt(dx * dx + dz * dz);
  if (dh < 0.4) return { near: canInteract(worker, target, 3.5, 5) };
  const nx = dx / dh, nz = dz / dh;
  const bx = Math.floor(loc.x + nx), bz = Math.floor(loc.z + nz);
  const by = Math.floor(loc.y);
  for (const yy of [by, by + 1]) {
    const cand = { x: bx, y: yy, z: bz };
    const id = blockIdAt(worker.dimension, cand);
    if (isSolid(id) && isBreakable(id)) {
      const k = keyV(cand);
      st.obstacleAttempts[k] = (st.obstacleAttempts[k] ?? 0) + 1;
      if (st.obstacleAttempts[k] > OBSTACLE_MAX_PER_TARGET * 4) return { failed: true };
      st.status = `${label}: engel kırıyor (${id.replace("minecraft:", "")})`;
      breakStep(worker, st, cand, { drop: "minecraft:air", skill: "mining" });
      return { working: true };
    }
  }
  // önümüz açık ama plan yok (ör. uçurum): hedefi karala
  return { failed: true };
}

/** Hedefe yaklaş + kır; tamamlandıysa {broke:true}. */
export function approachAndBreak(worker, st, target, opts, label) {
  const a = approachOrTunnel(worker, st, target, label);
  if (a.failed) { blacklistPos(st, target); return { failed: true }; }
  if (!a.near) return { working: true };
  const r = breakStep(worker, st, target, opts);
  if (r.done) return { broke: true, gone: r.gone };
  return { working: true };
}

/** Hedef hâlâ geçerli mi (id beklenen kümede)? */
export function targetValid(worker, pos, idSet) {
  const id = blockIdAt(worker.dimension, pos);
  return idSet.has ? idSet.has(id) : idSet.includes(id);
}
