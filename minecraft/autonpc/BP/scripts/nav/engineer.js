/**
 * AutoNPC v5.1 — MÜHENDİS MODU: yol yoksa yolu İNŞA ET.
 * A* başarısız olduğunda locomotion buraya düşer. Gerçek oyuncu teknikleri:
 *  - TÜNEL: öndeki ayak+kafa bloklarını gerçek süreyle kaz
 *  - KÖPRÜ: boşluk/uçurum/lav üstüne envanterden blok döşe
 *  - BASAMAK-KAZ: hedef yukarıda/çukurdaysa duvara merdiven oy (kaz + çık)
 *  - PİLLAR: dolgu varsa zıpla-altına-koy ile yüksel
 *  - MÜHÜR: bitişik lav/su kaynağını blokla kapat (kendini koruma)
 * Güvenlik: kendi ayağının altını ASLA kazmaz; lav komşuluğunu önce mühürler;
 * 600 denemede ilerleme yoksa 'stuck' raporlar (bedrock vb.).
 */
import { blockIdAt, setBlock, playSoundAt } from "../sys/blocks.js";
import { isSolid, isPassable, isLiquid, isBreakable, isHazard } from "../core/registry.js";
import { breakStep } from "../work/breaker.js";
import { countInv, removeInv } from "../core/state.js";
import { yawToward } from "../core/math.js";

const FILLERS = ["minecraft:cobblestone", "minecraft:dirt", "minecraft:netherrack", "minecraft:cobbled_deepslate", "minecraft:oak_planks"];
const DIRS4 = [[1, 0], [-1, 0], [0, 1], [0, -1]];
const eng = new Map(); // workerId -> {attempts, dirIdx}

export function clearEngineer(id) { eng.delete(id); }

function filler(st) { return FILLERS.find((f) => countInv(st, f) > 0); }

function placeFiller(worker, st, pos) {
  const f = filler(st);
  if (!f) return false;
  removeInv(st, f, 1);
  setBlock(worker.dimension, pos, f);
  playSoundAt(worker.dimension, "dig.stone", pos);
  try { worker.playAnimation("animation.autonpc.worker.swing"); } catch (e) { /* opsiyonel */ }
  return true;
}

/** bitişik lav hücresi varsa mühürle (kendini koruma). true = bu tick harcandı */
function sealAdjacentLava(worker, st, fx, fy, fz) {
  const dim = worker.dimension;
  for (const [ax, az] of DIRS4) {
    for (const ay of [0, 1]) {
      const p = { x: fx + ax, y: fy + ay, z: fz + az };
      const id = blockIdAt(dim, p);
      if (id === "minecraft:lava" || id === "minecraft:flowing_lava") {
        if (placeFiller(worker, st, p)) { st.status = "Mühendis: lavı mühürlüyor"; return true; }
      }
    }
  }
  return false;
}

function face(worker, dirx, dirz) {
  try {
    worker.teleport(worker.location, { dimension: worker.dimension, rotation: { x: 0, y: yawToward(dirx, dirz) } });
  } catch (e) { /* opsiyonel */ }
}

/** @returns {working:true} | {stuck:true} — her çağrı en fazla BİR eylem */
export function engineerStep(worker, st, target) {
  const dim = worker.dimension;
  const l = worker.location;
  const fx = Math.floor(l.x), fy = Math.floor(l.y), fz = Math.floor(l.z);
  let e = eng.get(worker.id);
  if (!e) { e = { ticks: 0, rot: 0, dirIdx: -1 }; eng.set(worker.id, e); }
  // SIM-S13 kök düzeltmesi: takılma = ÜRETKEN EYLEMSİZLİK, geçen süre değil.
  // Elle taş kazmak 110 tick/blok sürer; bu meşru çalışmadır. Yalnız sürekli
  // yön-değiştirme (hiçbir kazı/koyma/adım mümkün değil) stuck sayılır.
  if (++e.ticks > 6000) { eng.delete(worker.id); return { stuck: true }; }
  if (e.rot > 16) { eng.delete(worker.id); return { stuck: true }; }
  const rotate = () => { e.dirIdx = (e.dirIdx + 1); e.rot++; return { working: true }; };
  const productive = () => { e.rot = 0; return { working: true }; };

  if (sealAdjacentLava(worker, st, fx, fy, fz)) { e?.ticks; return (eng.get(worker.id).rot = 0), { working: true }; }

  const dxF = (Math.floor(target.x) + 0.5) - l.x;
  const dzF = (Math.floor(target.z) + 0.5) - l.z;
  const dy = Math.floor(target.y) - fy;
  let dirx, dirz;
  if (e.dirIdx >= 0) { [dirx, dirz] = DIRS4[e.dirIdx % 4]; }
  else if (Math.abs(dxF) >= Math.abs(dzF)) { dirx = Math.sign(dxF) || 1; dirz = 0; }
  else { dirx = 0; dirz = Math.sign(dzF) || 1; }
  const ax = fx + dirx, az = fz + dirz;
  face(worker, dirx, dirz);

  const boxed = DIRS4.every(([qx, qz]) =>
    isSolid(blockIdAt(dim, { x: fx + qx, y: fy, z: fz + qz }))
    || isSolid(blockIdAt(dim, { x: fx + qx, y: fy + 1, z: fz + qz })));

  // ---- YUKARI / ÇUKURDAN ÇIKIŞ: basamak-kaz (gerekirse pillar) ----
  // dy>=1: hedef yüzeydeyse son basamağa kadar TIRMAN (yeraltında bitirme)
  if (dy >= 1 || boxed) {
    const ceil = { x: fx, y: fy + 2, z: fz };
    const cId = blockIdAt(dim, ceil);
    if (isSolid(cId)) {
      if (!isBreakable(cId)) return rotate();
      st.status = "Mühendis: baş üstünü açıyor";
      breakStep(worker, st, ceil, { drop: "minecraft:air", skill: "mining" });
      return productive();
    }
    const stepFeet = { x: ax, y: fy + 1, z: az };
    const stepHead = { x: ax, y: fy + 2, z: az };
    for (const c of [stepFeet, stepHead]) {
      const id = blockIdAt(dim, c);
      if (isSolid(id)) {
        if (!isBreakable(id)) return rotate();
        st.status = "Mühendis: duvara basamak oyuyor";
        breakStep(worker, st, c, { skill: "mining" });
        return productive();
      }
    }
    const stepFloor = { x: ax, y: fy, z: az };
    if (!isSolid(blockIdAt(dim, stepFloor))) {
      if (placeFiller(worker, st, stepFloor)) { st.status = "Mühendis: basamak döşüyor"; return productive(); }
      // dolgu yok: pillar şansı da yok → yön değiştir
      e.dirIdx = (e.dirIdx + 1);
      return { working: true };
    }
    // basamağa çık
    worker.teleport({ x: ax + 0.5, y: fy + 1, z: az + 0.5 }, { dimension: dim, rotation: { x: 0, y: yawToward(dirx, dirz) } });
    st.status = "Mühendis: basamağa çıktı";
    e.dirIdx = -1;
    return productive();
  }

  // ---- AŞAĞI (derin hedef): güvenli merdiven-kaz ----
  if (dy <= -3) {
    const downFeet = { x: ax, y: fy - 1, z: az };
    const downHead = { x: ax, y: fy, z: az };
    const below2 = blockIdAt(dim, { x: ax, y: fy - 2, z: az });
    if (isLiquid(below2) || isHazard(below2)) return rotate();
    for (const c of [downHead, downFeet]) {
      const id = blockIdAt(dim, c);
      if (isSolid(id)) {
        if (!isBreakable(id)) return rotate();
        st.status = "Mühendis: merdiven kazıyor (aşağı)";
        breakStep(worker, st, c, { skill: "mining" });
        return productive();
      }
    }
    if (!isSolid(blockIdAt(dim, { x: ax, y: fy - 2, z: az }))) {
      if (placeFiller(worker, st, { x: ax, y: fy - 2, z: az })) return productive();
      e.dirIdx = (e.dirIdx + 1);
      return { working: true };
    }
    worker.teleport({ x: ax + 0.5, y: fy - 1, z: az + 0.5 }, { dimension: dim, rotation: { x: 0, y: yawToward(dirx, dirz) } });
    e.dirIdx = -1;
    return productive();
  }

  // ---- YATAY: tünel / köprü ----
  const feet = { x: ax, y: fy, z: az };
  const head = { x: ax, y: fy + 1, z: az };
  for (const c of [feet, head]) {
    const id = blockIdAt(dim, c);
    if (isSolid(id)) {
      if (!isBreakable(id)) return rotate();
      st.status = `Mühendis: engeli kazıyor (${id.replace("minecraft:", "")})`;
      breakStep(worker, st, c, { skill: "mining" });
      return productive();
    }
  }
  const floorId = blockIdAt(dim, { x: ax, y: fy - 1, z: az });
  if (!isSolid(floorId) || isHazard(floorId)) {
    // boşluk/lav/su: köprü döşe (lav-su hücresinin ÜSTÜNE değil, içine kapak)
    const bridgeCell = { x: ax, y: fy - 1, z: az };
    if (placeFiller(worker, st, bridgeCell)) { st.status = "Mühendis: köprü döşüyor"; return productive(); }
    return rotate();
  }
  // yol açık: bir hücre ilerle (A* bir sonraki tick devralabilir)
  worker.teleport({ x: ax + 0.5, y: fy, z: az + 0.5 }, { dimension: dim, rotation: { x: 0, y: yawToward(dirx, dirz) } });
  st.status = "Mühendis: ilerliyor";
  e.dirIdx = -1;
  return productive();
}
