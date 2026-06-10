/**
 * AutoNPC v5.0 — otomatik mod yönetmeni: gerçek oyuncu ilerleyişi.
 * odun → aletler → taş → demir → savaş seti (kılıç+kalkan+zırh) → ev →
 * elmas → büyü masası → yün/yatak → altın → NETHER → netherite.
 */
import { setTask, countInv, countAny } from "../core/state.js";
import { LOG_BLOCKS } from "../core/registry.js";
import { craftCombatSet, equipBestArmor } from "../combat/gear.js";
import { craft } from "../core/recipes.js";

export function directAuto(worker, st) {
  st.flags = st.flags ?? {};
  const logs = countAny(st, [...LOG_BLOCKS]) + countInv(st, "minecraft:oak_planks");

  if (logs < 12) return setTask(st, "gather_wood", { tree: "any", amount: 16, auto: true });
  if (countInv(st, "minecraft:cobblestone") < 12) return setTask(st, "collect_block", { blockId: "minecraft:stone", amount: 16, auto: true });
  if (countInv(st, "minecraft:iron_ingot") + countInv(st, "minecraft:raw_iron") < 12) {
    return setTask(st, "mine_ore", { group: "iron", amount: 12, auto: true });
  }
  if (countInv(st, "minecraft:coal") < 8) return setTask(st, "mine_ore", { group: "coal", amount: 8, auto: true });

  // demiri erit + savaş setini kur
  while (countInv(st, "minecraft:raw_iron") > 0 && countInv(st, "minecraft:coal") > 1) {
    if (!craft(st, "minecraft:iron_ingot").ok) break;
  }
  craftCombatSet(st);
  equipBestArmor(worker, st);

  if (!st.flags.houseBuilt) return setTask(st, "build_house", { auto: true });
  if (countInv(st, "minecraft:diamond") < 5) return setTask(st, "mine_ore", { group: "diamond", amount: 5, auto: true });

  if (!st.flags.enchantTable) {
    const r = craft(st, "minecraft:enchanting_table");
    if (r.ok) st.flags.enchantTable = true;
    else if (r.missing.item === "minecraft:obsidian") return setTask(st, "collect_block", { blockId: "minecraft:obsidian", amount: 4, auto: true });
    else st.flags.enchantTable = "skip"; // kitap malzemesi yoksa takılma
    st.dirty = true;
  }
  if (countInv(st, "minecraft:wool") < 12 && countInv(st, "minecraft:bed") < 4) {
    return setTask(st, "hunt", { animal: "sheep", amount: 4, auto: true });
  }
  if (countInv(st, "minecraft:gold_ingot") + countInv(st, "minecraft:raw_gold") < 4) {
    return setTask(st, "mine_ore", { group: "gold", amount: 4, auto: true });
  }
  if (!st.flags.netherDone) return setTask(st, "nether_quest", { auto: true });

  // her şey tamam: devriye/balık
  return setTask(st, "fish", { amount: 5, auto: true });
}
