/**
 * AutoNPC v4.0 — bütçeli grid A*. (D3 düzeltmesi)
 * v3 hareketi knockback/impulse hack'iydi; v4 blok-grid üzerinde gerçek yol bulur.
 * Sınır: ASTAR_MAX_NODES — aşılırsa hedefe en yakın düğüme KISMİ yol döner
 * (worker ilerler, bir sonraki planda devam eder).
 */
import { standable, stepTarget } from "./grid.js";
import { ASTAR_MAX_NODES } from "../core/config.js";

const DIRS = [
  [1, 0], [-1, 0], [0, 1], [0, -1],
  [1, 1], [1, -1], [-1, 1], [-1, -1],
];

function k3(x, y, z) { return x + "," + y + "," + z; }
function heur(x, y, z, t) { return Math.abs(x - t.x) + Math.abs(y - t.y) * 0.6 + Math.abs(z - t.z); }

/** Başlangıcı yürünebilir bir hücreye oturt (NPC blok kenarında olabilir). */
function snapStart(dim, p) {
  const x = Math.floor(p.x), z = Math.floor(p.z);
  for (const dy of [0, -1, 1, -2, 2]) {
    if (standable(dim, x, Math.floor(p.y) + dy, z)) return { x, y: Math.floor(p.y) + dy, z };
  }
  return { x, y: Math.floor(p.y), z };
}

/**
 * @returns {{path: {x,y,z}[], complete: boolean} | undefined}
 * path: ayak hücreleri dizisi (başlangıç hariç). Hedefe `reach` hücre kala tamamlanmış sayılır.
 */
export function findPath(dim, fromLoc, target, reach = 1) {
  const start = snapStart(dim, fromLoc);
  const goal = { x: Math.floor(target.x), y: Math.floor(target.y), z: Math.floor(target.z) };

  const open = [{ x: start.x, y: start.y, z: start.z, g: 0, f: heur(start.x, start.y, start.z, goal) }];
  const came = new Map();
  const gScore = new Map([[k3(start.x, start.y, start.z), 0]]);
  let best = open[0], bestH = heur(start.x, start.y, start.z, goal);
  let expanded = 0;

  while (open.length && expanded < ASTAR_MAX_NODES) {
    // küçük open listelerinde lineer min yeterli (N<=ASTAR_MAX_NODES)
    let bi = 0;
    for (let i = 1; i < open.length; i++) if (open[i].f < open[bi].f) bi = i;
    const cur = open.splice(bi, 1)[0];
    expanded++;

    const h = heur(cur.x, cur.y, cur.z, goal);
    if (h < bestH) { bestH = h; best = cur; }

    const dx = Math.abs(cur.x - goal.x), dz = Math.abs(cur.z - goal.z), dy = Math.abs(cur.y - goal.y);
    if (dx <= reach && dz <= reach && dy <= 2) {
      return { path: rebuild(came, cur), complete: true };
    }

    for (const [sx, sz] of DIRS) {
      const diag = sx !== 0 && sz !== 0;
      if (diag) {
        // köşe kesme yok: iki kardinal de geçilebilir olmalı
        if (stepTarget(dim, cur.x, cur.y, cur.z, sx, 0) === undefined) continue;
        if (stepTarget(dim, cur.x, cur.y, cur.z, 0, sz) === undefined) continue;
      }
      const ny = stepTarget(dim, cur.x, cur.y, cur.z, sx, sz);
      if (ny === undefined) continue;
      const nx = cur.x + sx, nz = cur.z + sz;
      const stepCost = (diag ? 1.41 : 1) + Math.abs(ny - cur.y) * 0.4;
      const ng = cur.g + stepCost;
      const nk = k3(nx, ny, nz);
      if (ng >= (gScore.get(nk) ?? Infinity)) continue;
      gScore.set(nk, ng);
      came.set(nk, cur);
      open.push({ x: nx, y: ny, z: nz, g: ng, f: ng + heur(nx, ny, nz, goal) });
    }
  }

  if (best && (best.x !== start.x || best.z !== start.z || best.y !== start.y)) {
    return { path: rebuild(came, best), complete: false };
  }
  return undefined;
}

function rebuild(came, node) {
  const out = [];
  let cur = node;
  while (cur) {
    out.push({ x: cur.x, y: cur.y, z: cur.z });
    cur = came.get(k3(cur.x, cur.y, cur.z));
  }
  out.reverse();
  out.shift(); // başlangıç hücresi
  return out;
}
