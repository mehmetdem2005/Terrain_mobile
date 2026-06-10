/**
 * AutoNPC v4.0 — yürünebilirlik sorguları (A* ve locomotion'ın ortak zemini).
 * Kural: ayak+kafa pasif, taban katı, tabanda/içinde tehlike yok.
 */
import { blockIdAt } from "../sys/blocks.js";
import { isPassable, isSolid, isHazard, isLiquid } from "../core/registry.js";
import { MAX_FALL, STEP_UP } from "../core/config.js";

export function standable(dim, x, y, z) {
  const feet = blockIdAt(dim, { x, y, z });
  const head = blockIdAt(dim, { x, y: y + 1, z });
  const below = blockIdAt(dim, { x, y: y - 1, z });
  if (!isPassable(feet) || !isPassable(head)) return false;
  if (!isSolid(below)) return false;
  if (isHazard(below) || isHazard(feet) || isLiquid(feet)) return false;
  return true;
}

/**
 * (x,y,z)'den yatay (dx,dz) yönüne geçilebilecek hedef y'yi döndürür; geçilemiyorsa undefined.
 * Adım-yukarı STEP_UP, güvenli düşüş MAX_FALL.
 */
export function stepTarget(dim, x, y, z, dx, dz) {
  const nx = x + dx, nz = z + dz;
  // aynı seviye
  if (standable(dim, nx, y, nz)) return y;
  // yukarı adım (üstte kafa boşluğu da gerekli)
  for (let up = 1; up <= STEP_UP; up++) {
    if (standable(dim, nx, y + up, nz)) {
      const ceiling = blockIdAt(dim, { x, y: y + 1 + up, z });
      if (isPassable(ceiling)) return y + up;
      return undefined;
    }
  }
  // aşağı düşüş
  for (let down = 1; down <= MAX_FALL; down++) {
    const fy = y - down;
    const through = blockIdAt(dim, { x: nx, y: fy + 1, z: nz });
    if (!isPassable(through)) return undefined; // düşüş kanalı tıkalı
    if (standable(dim, nx, fy, nz)) return fy;
  }
  return undefined;
}
