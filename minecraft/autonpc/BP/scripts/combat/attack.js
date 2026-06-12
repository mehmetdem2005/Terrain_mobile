/**
 * AutoNPC v5.0 — saldırı: yakında kılıç (gerçek applyDamage + animasyon),
 * uzakta yay (gerçek ok projektili). Loot oyun tarafından doğal düşer.
 */
import { EntityDamageCause } from "@minecraft/server";
import { bestSword, SWORD_DAMAGE } from "./gear.js";
import { equipMainhand } from "../sys/equipment.js";
import { countInv, removeInv } from "../core/state.js";
import { faceBlock } from "../nav/locomotion.js";
import { dist, floorV } from "../core/math.js";

const cooldowns = new Map(); // workerId -> tick sayacı

export function tickCooldown(workerId) {
  const c = cooldowns.get(workerId) ?? 0;
  if (c > 0) cooldowns.set(workerId, c - 1);
}

export function meleeAttack(worker, st, target) {
  if ((cooldowns.get(worker.id) ?? 0) > 0) return false;
  const sword = bestSword(st);
  if (sword && st.held !== sword) equipMainhand(worker, st, sword);
  faceBlock(worker, floorV(target.location));
  try { worker.playAnimation("animation.autonpc.worker.attack"); } catch (e) { /* opsiyonel */ }
  try {
    target.applyDamage(SWORD_DAMAGE[sword ?? "hand"] ?? 1, {
      cause: EntityDamageCause.entityAttack,
      damagingEntity: worker,
    });
  } catch (e) { return false; }
  cooldowns.set(worker.id, 12); // ~0.6s vuruş aralığı (vanilla kılıç temposu)
  st.skills.mining; // no-op; skill eklenmez, savaş ayrı sayaç değil
  return true;
}

export function canShoot(st) {
  return countInv(st, "minecraft:bow") > 0 && countInv(st, "minecraft:arrow") > 0;
}

export function bowAttack(worker, st, target) {
  if ((cooldowns.get(worker.id) ?? 0) > 0) return false;
  if (!canShoot(st)) return false;
  if (st.held !== "minecraft:bow") equipMainhand(worker, st, "minecraft:bow");
  faceBlock(worker, floorV(target.location));
  try { worker.playAnimation("animation.autonpc.worker.attack"); } catch (e) { /* opsiyonel */ }
  try {
    const from = { x: worker.location.x, y: worker.location.y + 1.5, z: worker.location.z };
    const to = { x: target.location.x, y: target.location.y + 1.0, z: target.location.z };
    const d = dist(from, to);
    const vel = {
      x: (to.x - from.x) / d * 1.6,
      y: (to.y - from.y) / d * 1.6 + d * 0.012, // balistik telafi
      z: (to.z - from.z) / d * 1.6,
    };
    const arrow = worker.dimension.spawnEntity("minecraft:arrow", from);
    const proj = arrow.getComponent("minecraft:projectile");
    if (proj) { proj.owner = worker; proj.shoot(vel); }
    else arrow.applyImpulse(vel);
    removeInv(st, "minecraft:arrow", 1);
  } catch (e) { return false; }
  cooldowns.set(worker.id, 24); // yay temposu
  return true;
}
