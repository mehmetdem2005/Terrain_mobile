/**
 * AutoNPC v5.0 — silah hasarı, zırh koruması, kuşanma.
 * Vanilla değer tabloları; zırh azaltımı entityHurt telafisiyle uygulanır
 * (custom entity'de gerçek armor attribute'u yok — dürüst simülasyon).
 */
import { EquipmentSlot, ItemStack } from "@minecraft/server";
import { countInv } from "../core/state.js";
import { craft } from "../core/recipes.js";

export const SWORD_DAMAGE = {
  "minecraft:netherite_sword": 8, "minecraft:diamond_sword": 7,
  "minecraft:iron_sword": 6, "minecraft:stone_sword": 5,
  "minecraft:wooden_sword": 4, hand: 1,
};
export const SWORD_ORDER = Object.keys(SWORD_DAMAGE).filter((k) => k !== "hand");

/** Vanilla zırh puanları (tam set demir=15, elmas=20, netherite=20+tokluk). */
export const ARMOR_POINTS = {
  "minecraft:iron_helmet": 2, "minecraft:iron_chestplate": 6, "minecraft:iron_leggings": 5, "minecraft:iron_boots": 2,
  "minecraft:diamond_helmet": 3, "minecraft:diamond_chestplate": 8, "minecraft:diamond_leggings": 6, "minecraft:diamond_boots": 3,
  "minecraft:netherite_helmet": 3, "minecraft:netherite_chestplate": 8, "minecraft:netherite_leggings": 6, "minecraft:netherite_boots": 3,
};
const SLOT_OF = { helmet: EquipmentSlot.Head, chestplate: EquipmentSlot.Chest, leggings: EquipmentSlot.Legs, boots: EquipmentSlot.Feet };

export function bestSword(st) {
  for (const s of SWORD_ORDER) if (countInv(st, s) > 0) return s;
  return undefined;
}

export function armorPoints(st) {
  let p = 0;
  for (const id of Object.values(st.equipment ?? {})) p += ARMOR_POINTS[id] ?? 0;
  return p;
}

function setSlot(worker, slot, itemId) {
  try {
    const eq = worker.getComponent("minecraft:equippable");
    if (!eq) return false;
    eq.setEquipment(slot, itemId ? new ItemStack(itemId, 1) : undefined);
    return true;
  } catch (e) { return false; }
}

/** Envanterdeki en iyi zırh parçalarını kuşan (görsel + st.equipment). */
export function equipBestArmor(worker, st) {
  st.equipment = st.equipment ?? { head: "", chest: "", legs: "", feet: "", offhand: "" };
  const tiers = ["netherite", "diamond", "iron"];
  const map = { helmet: "head", chestplate: "chest", leggings: "legs", boots: "feet" };
  let changed = false;
  for (const [piece, key] of Object.entries(map)) {
    for (const tier of tiers) {
      const id = `minecraft:${tier}_${piece}`;
      if (countInv(st, id) > 0 && st.equipment[key] !== id) {
        st.equipment[key] = id;
        setSlot(worker, SLOT_OF[piece], id);
        changed = true;
        break;
      }
      if (st.equipment[key] === id) break; // zaten en iyisi
    }
  }
  if (changed) st.dirty = true;
  return changed;
}

export function equipShield(worker, st, on) {
  st.equipment = st.equipment ?? { head: "", chest: "", legs: "", feet: "", offhand: "" };
  const want = on && countInv(st, "minecraft:shield") > 0 ? "minecraft:shield" : "";
  if (st.equipment.offhand === want) return;
  st.equipment.offhand = want;
  setSlot(worker, EquipmentSlot.Offhand, want || undefined);
  st.dirty = true;
}

/** Savaş seti craft zinciri: kılıç → kalkan → demir zırh (malzeme yettiğince). */
export function craftCombatSet(st) {
  const made = [];
  if (!bestSword(st)) {
    for (const s of ["minecraft:iron_sword", "minecraft:stone_sword", "minecraft:wooden_sword"]) {
      if (craft(st, s).ok) { made.push(s); break; }
    }
  }
  if (countInv(st, "minecraft:shield") < 1 && craft(st, "minecraft:shield").ok) made.push("shield");
  for (const piece of ["helmet", "chestplate", "leggings", "boots"]) {
    const id = `minecraft:iron_${piece}`;
    if ((countInv(st, id) + countInv(st, `minecraft:diamond_${piece}`) + countInv(st, `minecraft:netherite_${piece}`)) < 1) {
      if (craft(st, id).ok) made.push(id);
    }
  }
  return made;
}
