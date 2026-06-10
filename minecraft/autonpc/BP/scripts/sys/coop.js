/**
 * AutoNPC v5.2 — İŞBİRLİĞİ PROTOKOLÜ: işçiler birbirine yardım eder.
 * Takılan işçi (watchdog nudge / mühendis stuck) imdat yayınlar; boşta veya
 * oto-moddaki başka bir işçi çağrıyı SAHİPLENİR, konuma gider, etrafını
 * kazarak kurtarır, sonra kendi işine döner.
 */
import { angry } from "../chat/personality.js";

const calls = new Map(); // stuckWorkerId -> {pos, dimId, reason, claimedBy, age}

export function requestHelp(worker, st, reason) {
  if (calls.has(worker.id)) return;
  calls.set(worker.id, {
    pos: { x: Math.floor(worker.location.x), y: Math.floor(worker.location.y), z: Math.floor(worker.location.z) },
    dimId: worker.dimension.id,
    reason,
    claimedBy: undefined,
    age: 0,
  });
  angry(st, "distress");
}

export function cancelHelp(workerId) { calls.delete(workerId); }

export function tickCalls() {
  for (const [id, c] of calls) {
    if (++c.age > 2400) calls.delete(id); // 2dk sahipsiz çağrı düşer
  }
}

/** Boştaki işçi için uygun çağrı bul ve sahiplen. */
export function claimRescue(rescuer) {
  for (const [stuckId, c] of calls) {
    if (stuckId === rescuer.id) continue;
    if (c.claimedBy && c.claimedBy !== rescuer.id) continue;
    if (c.dimId !== rescuer.dimension.id) continue;
    c.claimedBy = rescuer.id;
    return { stuckId, ...c };
  }
  return undefined;
}

export function callFor(stuckId) { return calls.get(stuckId); }
