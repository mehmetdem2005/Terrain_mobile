/**
 * AutoNPC v4.0 — devam-edebilir blok tarayıcı. (D6 düzeltmesi)
 * v3 scanNearestBlock tek tick'te O(r³) blok okuyordu ve y-katmanı önyargısı
 * "en yakını" vermiyordu. v4: kabuk-kabuk üretici; tick başına
 * SCAN_BLOCKS_PER_TICK okuma; kabuk tamamlanınca o kabuktaki EN YAKIN aday döner.
 */
import { shellPositions, floorV, dist } from "../core/math.js";
import { blockIdAt } from "../sys/blocks.js";
import { SCAN_BLOCKS_PER_TICK } from "../core/config.js";

const scans = new Map(); // workerId:tag -> {gen, base, radius, best, bestD, shellR}

export function resetScan(workerId, tag) { scans.delete(workerId + ":" + tag); }

/**
 * Her tick çağrılır; bulduysa {found}, bitti+yok ise {exhausted}, sürüyor ise {scanning}.
 * predicate(blockId, pos) hedefi tanımlar.
 */
export function scanStep(worker, tag, radius, predicate) {
  const id = worker.id + ":" + tag;
  let s = scans.get(id);
  const base = floorV(worker.location);
  if (!s || s.radius !== radius) {
    s = { gen: shellPositions(base, radius), base, radius, best: undefined, bestD: Infinity, lastR: 0 };
    scans.set(id, s);
  }
  const dim = worker.dimension;
  for (let i = 0; i < SCAN_BLOCKS_PER_TICK; i++) {
    const n = s.gen.next();
    if (n.done) {
      scans.delete(id);
      if (s.best) return { found: s.best };
      return { exhausted: true };
    }
    const pos = n.value;
    const r = Math.max(Math.abs(pos.x - s.base.x), Math.abs(pos.z - s.base.z));
    // kabuk r tamamlandıysa ve aday varsa: daha dış kabuk daha yakın olamaz → erken çık
    if (r > s.lastR) {
      if (s.best) { scans.delete(id); return { found: s.best }; }
      s.lastR = r;
    }
    const bid = blockIdAt(dim, pos);
    if (!predicate(bid, pos)) continue;
    const d = dist(s.base, pos);
    if (d < s.bestD) { s.best = { x: pos.x, y: pos.y, z: pos.z, id: bid }; s.bestD = d; }
  }
  return { scanning: true };
}
