/** AutoNPC v4.0 — vektör/grid yardımcıları. Saf fonksiyonlar, yan etki yok. */

export function floorV(v) { return { x: Math.floor(v.x), y: Math.floor(v.y), z: Math.floor(v.z) }; }
export function centerV(p) { return { x: Math.floor(p.x) + 0.5, y: Math.floor(p.y), z: Math.floor(p.z) + 0.5 }; }
export function keyV(p) { return `${Math.floor(p.x)},${Math.floor(p.y)},${Math.floor(p.z)}`; }
export function sameBlock(a, b) {
  return Math.floor(a.x) === Math.floor(b.x) && Math.floor(a.y) === Math.floor(b.y) && Math.floor(a.z) === Math.floor(b.z);
}
export function dist(a, b) {
  const dx = a.x - b.x, dy = (a.y ?? 0) - (b.y ?? 0), dz = a.z - b.z;
  return Math.sqrt(dx * dx + dy * dy + dz * dz);
}
export function horizDist(a, b) {
  const dx = a.x - b.x, dz = a.z - b.z;
  return Math.sqrt(dx * dx + dz * dz);
}
export function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }
export function yawToward(dx, dz) { return Math.atan2(-dx, dz) * 180 / Math.PI; }

/** Genişleyen küp kabuğu üreticisi: r=0,1,2... kabuklarındaki blokları sırayla verir.
 *  D6 düzeltmesinin temeli: tarayıcı bu üreticiyi tick'ler arasında DEVAM ettirir. */
export function* shellPositions(base, maxR, yMin = -4, yMax = 5) {
  for (let r = 0; r <= maxR; r++) {
    for (let y = yMin; y <= yMax; y++) {
      if (r === 0) { yield { x: base.x, y: base.y + y, z: base.z }; continue; }
      for (let dx = -r; dx <= r; dx++) {
        for (let dz = -r; dz <= r; dz++) {
          if (Math.abs(dx) !== r && Math.abs(dz) !== r) continue;
          yield { x: base.x + dx, y: base.y + y, z: base.z + dz };
        }
      }
    }
  }
}
