/**
 * AutoNPC v4.0 — güvenli blok erişimi + doğal kırma. (D2 düzeltmesi)
 * v3 runCommandAsync kullanıyordu; @minecraft/server 2.0'da KALDIRILDI ve
 * doğal drop zinciri sessizce ölüyordu. v4 sync dimension.runCommand kullanır.
 */
import { ItemStack } from "@minecraft/server";
import { isAir } from "../core/registry.js";

export function blockAt(dim, pos) {
  try { return dim.getBlock({ x: Math.floor(pos.x), y: Math.floor(pos.y), z: Math.floor(pos.z) }); }
  catch (e) { return undefined; } // yüklü olmayan chunk
}
export function blockIdAt(dim, pos) { return blockAt(dim, pos)?.typeId ?? "minecraft:air"; }

/** Bloğu doğal drop üreterek kır. Dönen değer: drop'un oyun tarafından üretilip üretilmediği. */
export function naturalBreak(dim, pos) {
  const x = Math.floor(pos.x), y = Math.floor(pos.y), z = Math.floor(pos.z);
  try {
    dim.runCommand(`setblock ${x} ${y} ${z} air destroy`);
    return true;
  } catch (e) {
    // komut reddedildiyse (ör. eğitim modu kısıtı) sessiz silmeye düş:
    try { blockAt(dim, pos)?.setType("minecraft:air"); } catch (e2) { /* chunk yok */ }
    return false;
  }
}

export function spawnItemAt(dim, typeId, pos, amount = 1) {
  if (!typeId || isAir(typeId)) return false;
  try {
    dim.spawnItem(new ItemStack(typeId, amount), { x: pos.x + 0.5, y: pos.y + 0.5, z: pos.z + 0.5 });
    return true;
  } catch (e) { return false; }
}

export function setBlock(dim, pos, typeId) {
  try { blockAt(dim, pos)?.setType(typeId); return true; } catch (e) { return false; }
}

export function itemStackOf(entity) {
  try {
    const s = entity.getComponent("minecraft:item")?.itemStack;
    if (s?.typeId) return { typeId: s.typeId, amount: s.amount ?? 1 };
  } catch (e) { /* entity ölü */ }
  return undefined;
}

export function playSoundAt(dim, sound, pos, volume = 0.45) {
  try { dim.playSound(sound, { x: pos.x + 0.5, y: pos.y + 0.5, z: pos.z + 0.5 }, { volume }); }
  catch (e) { /* ses opsiyonel */ }
}
export function particleAt(dim, id, pos) {
  try { dim.spawnParticle(id, { x: pos.x + 0.5, y: pos.y + 0.6, z: pos.z + 0.5 }); }
  catch (e) { /* partikül opsiyonel */ }
}
