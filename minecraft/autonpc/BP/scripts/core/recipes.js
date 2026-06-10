/**
 * AutoNPC v5.0 — craft tarifleri tek tablo + jenerik üretici.
 * Sanal envanterden malzeme düşer; eksikse {missing} döner (görevler alt-görev türetir).
 */
import { countInv, addInv, removeInv } from "./state.js";

// out -> { count, needs: {item: adet}, station? }
export const RECIPES = {
  "minecraft:oak_planks": { count: 4, needs: { "#log": 1 } },
  "minecraft:stick": { count: 4, needs: { "minecraft:oak_planks": 2 } },
  "minecraft:torch": { count: 4, needs: { "minecraft:coal": 1, "minecraft:stick": 1 } },
  "minecraft:crafting_table": { count: 1, needs: { "minecraft:oak_planks": 4 } },
  "minecraft:furnace": { count: 1, needs: { "minecraft:cobblestone": 8 } },
  "minecraft:chest": { count: 1, needs: { "minecraft:oak_planks": 8 } },
  "minecraft:bed": { count: 1, needs: { "minecraft:wool": 3, "minecraft:oak_planks": 3 } },
  "minecraft:shield": { count: 1, needs: { "minecraft:oak_planks": 6, "minecraft:iron_ingot": 1 } },
  "minecraft:bow": { count: 1, needs: { "minecraft:stick": 3, "minecraft:string": 3 } },
  "minecraft:arrow": { count: 4, needs: { "minecraft:flint": 1, "minecraft:stick": 1, "minecraft:feather": 1 } },
  "minecraft:fishing_rod": { count: 1, needs: { "minecraft:stick": 3, "minecraft:string": 2 } },
  "minecraft:flint_and_steel": { count: 1, needs: { "minecraft:iron_ingot": 1, "minecraft:flint": 1 } },
  "minecraft:book": { count: 1, needs: { "minecraft:paper": 3, "minecraft:leather": 1 } },
  "minecraft:paper": { count: 3, needs: { "minecraft:sugar_cane": 3 } },
  "minecraft:enchanting_table": { count: 1, needs: { "minecraft:obsidian": 4, "minecraft:diamond": 2, "minecraft:book": 1 } },
  // silahlar
  "minecraft:wooden_sword": { count: 1, needs: { "minecraft:oak_planks": 2, "minecraft:stick": 1 } },
  "minecraft:stone_sword": { count: 1, needs: { "minecraft:cobblestone": 2, "minecraft:stick": 1 } },
  "minecraft:iron_sword": { count: 1, needs: { "minecraft:iron_ingot": 2, "minecraft:stick": 1 } },
  "minecraft:diamond_sword": { count: 1, needs: { "minecraft:diamond": 2, "minecraft:stick": 1 } },
  // zırh (demir + elmas setleri)
  "minecraft:iron_helmet": { count: 1, needs: { "minecraft:iron_ingot": 5 } },
  "minecraft:iron_chestplate": { count: 1, needs: { "minecraft:iron_ingot": 8 } },
  "minecraft:iron_leggings": { count: 1, needs: { "minecraft:iron_ingot": 7 } },
  "minecraft:iron_boots": { count: 1, needs: { "minecraft:iron_ingot": 4 } },
  "minecraft:diamond_helmet": { count: 1, needs: { "minecraft:diamond": 5 } },
  "minecraft:diamond_chestplate": { count: 1, needs: { "minecraft:diamond": 8 } },
  "minecraft:diamond_leggings": { count: 1, needs: { "minecraft:diamond": 7 } },
  "minecraft:diamond_boots": { count: 1, needs: { "minecraft:diamond": 4 } },
  // eritme/netherite (fırın+smithing simülasyonu: yakıt = kömür)
  "minecraft:iron_ingot": { count: 1, needs: { "minecraft:raw_iron": 1, "minecraft:coal": 1 }, station: "furnace" },
  "minecraft:gold_ingot": { count: 1, needs: { "minecraft:raw_gold": 1, "minecraft:coal": 1 }, station: "furnace" },
  "minecraft:netherite_scrap": { count: 1, needs: { "minecraft:ancient_debris": 1, "minecraft:coal": 1 }, station: "furnace" },
  "minecraft:netherite_ingot": { count: 1, needs: { "minecraft:netherite_scrap": 4, "minecraft:gold_ingot": 4 } },
  "minecraft:netherite_sword": { count: 1, needs: { "minecraft:diamond_sword": 1, "minecraft:netherite_ingot": 1 }, station: "smithing" },
  "minecraft:netherite_helmet": { count: 1, needs: { "minecraft:diamond_helmet": 1, "minecraft:netherite_ingot": 1 }, station: "smithing" },
  "minecraft:netherite_chestplate": { count: 1, needs: { "minecraft:diamond_chestplate": 1, "minecraft:netherite_ingot": 1 }, station: "smithing" },
  "minecraft:netherite_leggings": { count: 1, needs: { "minecraft:diamond_leggings": 1, "minecraft:netherite_ingot": 1 }, station: "smithing" },
  "minecraft:netherite_boots": { count: 1, needs: { "minecraft:diamond_boots": 1, "minecraft:netherite_ingot": 1 }, station: "smithing" },
  "minecraft:netherite_pickaxe": { count: 1, needs: { "minecraft:diamond_pickaxe": 1, "minecraft:netherite_ingot": 1 }, station: "smithing" },
};

import { LOG_BLOCKS } from "./registry.js";

function haveOf(st, need) {
  if (need === "#log") return [...LOG_BLOCKS].reduce((n, id) => n + countInv(st, id), 0);
  return countInv(st, need);
}
function consume(st, need, qty) {
  if (need !== "#log") { removeInv(st, need, qty); return; }
  let left = qty;
  for (const id of LOG_BLOCKS) {
    if (left <= 0) break;
    left -= removeInv(st, id, left);
  }
}

/** @returns {ok:true} | {missing:{item,qty}} */
export function craft(st, outId, times = 1) {
  const r = RECIPES[outId];
  if (!r) return { missing: { item: outId, qty: 1 } };
  for (let t = 0; t < times; t++) {
    for (const [need, qty] of Object.entries(r.needs)) {
      const have = haveOf(st, need);
      if (have < qty) {
        // ara ürünü craft etmeyi dene (1 seviye derin zincir: planks/stick/ingot...)
        if (need !== "#log" && RECIPES[need]) {
          const sub = craft(st, need, Math.ceil((qty - have) / RECIPES[need].count));
          if (sub.ok) continue;
          return sub;
        }
        return { missing: { item: need, qty: qty - have } };
      }
    }
    for (const [need, qty] of Object.entries(r.needs)) consume(st, need, qty);
    addInv(st, outId, r.count);
    st.skills.crafting++;
  }
  return { ok: true };
}

/** Hedef adede kadar craft; eksik malzemeyi rapor eder. */
export function craftUpTo(st, outId, target) {
  while (countInv(st, outId) < target) {
    const r = craft(st, outId, 1);
    if (!r.ok) return r;
  }
  return { ok: true };
}
