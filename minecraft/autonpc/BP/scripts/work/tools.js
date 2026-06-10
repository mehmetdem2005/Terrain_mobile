/**
 * AutoNPC v4.0 — alet seçimi ve craft zinciri.
 * Sanal envanterden en iyi aleti seçer; yoksa malzeme alt-görevleri talep eder.
 */
import {
  TOOL_ORDER, toolClassFor, harvestLevelFor, toolItemId, isToolItem,
  LOG_BLOCKS,
} from "../core/registry.js";
import { countInv, addInv, removeInv, pushSubTask } from "../core/state.js";
import { equipMainhand } from "../sys/equipment.js";

function totalLogs(st) { return [...LOG_BLOCKS].reduce((n, id) => n + countInv(st, id), 0); }

export function bestToolFor(st, blockId) {
  const cls = toolClassFor(blockId);
  if (cls === "hand") return "minecraft:air";
  for (const tier of TOOL_ORDER) {
    const id = toolItemId(tier, cls);
    if (countInv(st, id) > 0) return id;
  }
  return "minecraft:air";
}

export function equipBestTool(worker, st, blockId) {
  const best = bestToolFor(st, blockId);
  if (best !== "minecraft:air") { equipMainhand(worker, st, best); return best; }
  if (!isToolItem(st.held)) equipMainhand(worker, st, "minecraft:air");
  return st.held;
}

export function craftPlanks(st, minPlanks) {
  while (countInv(st, "minecraft:oak_planks") < minPlanks) {
    const log = [...LOG_BLOCKS].find((id) => countInv(st, id) > 0);
    if (!log) return false;
    removeInv(st, log, 1);
    addInv(st, "minecraft:oak_planks", 4);
    st.skills.crafting++;
  }
  return true;
}

export function craftSticks(st, minSticks) {
  craftPlanks(st, 2);
  while (countInv(st, "minecraft:stick") < minSticks) {
    if (countInv(st, "minecraft:oak_planks") < 2) return false;
    removeInv(st, "minecraft:oak_planks", 2);
    addInv(st, "minecraft:stick", 4);
    st.skills.crafting++;
  }
  return true;
}

export function craftTool(st, tier, cls) {
  const item = toolItemId(tier, cls);
  if (countInv(st, item) > 0) return true;
  if (!craftSticks(st, 2)) return false;
  let material = "minecraft:oak_planks";
  if (tier === "stone") {
    material = countInv(st, "minecraft:cobblestone") >= 3 ? "minecraft:cobblestone" : "minecraft:cobbled_deepslate";
  } else if (tier === "iron") {
    material = "minecraft:iron_ingot";
  } else if (tier === "wood") {
    if (!craftPlanks(st, 3)) return false;
  }
  if (countInv(st, material) < 3) return false;
  removeInv(st, "minecraft:stick", 2);
  removeInv(st, material, 3);
  addInv(st, item, 1);
  st.skills.crafting++;
  return true;
}

/**
 * Blok için yeterli alet garantile. Yoksa craft dener; malzeme yoksa alt-görev
 * iter ve false döner (görev bir sonraki tick alt-görevden devam eder).
 */
export function ensureToolFor(st, blockId) {
  const need = harvestLevelFor(blockId);
  if (need === "hand") return true;
  if (bestToolFor(st, blockId) !== "minecraft:air") {
    // elindeki en iyi alet seviyesi yetiyor mu kontrolü breaker'da (canHarvest) yapılır;
    // burada en azından sınıf aletinin varlığı yeterli kabul edilir, gerekirse tier yükseltilir.
  }
  const cls = toolClassFor(blockId);
  if (cls !== "pickaxe") {
    // balta/kürek: tahta üret yeter
    if (bestToolFor(st, blockId) !== "minecraft:air") return true;
    if (craftTool(st, "wood", cls)) return true;
    if (totalLogs(st) < 2) { pushSubTask(st, "gather_wood", { tree: "any", amount: 4, reason: "tool" }); return false; }
    return craftTool(st, "wood", cls);
  }
  // kazma zinciri: tahta → taş → (demir hedefse) demir
  const order = need === "iron" ? ["iron", "stone", "wood"] : need === "stone" ? ["stone", "wood"] : ["wood"];
  for (const tier of order) if (countInv(st, toolItemId(tier, "pickaxe")) > 0) return true;
  if (need === "wood" || need === "hand") {
    if (craftTool(st, "wood", "pickaxe")) return true;
    if (totalLogs(st) < 2) { pushSubTask(st, "gather_wood", { tree: "any", amount: 6, reason: "tool" }); return false; }
    return craftTool(st, "wood", "pickaxe");
  }
  // taş+ kazma gerekiyor
  if (craftTool(st, "stone", "pickaxe")) return true;
  if (countInv(st, "minecraft:cobblestone") + countInv(st, "minecraft:cobbled_deepslate") < 3) {
    // önce tahta kazma (taş kazabilmek için)
    if (bestToolFor(st, "minecraft:stone") === "minecraft:air" && !craftTool(st, "wood", "pickaxe")) {
      if (totalLogs(st) < 2) { pushSubTask(st, "gather_wood", { tree: "any", amount: 6, reason: "tool" }); return false; }
      craftTool(st, "wood", "pickaxe");
    }
    pushSubTask(st, "collect_block", { blockId: "minecraft:stone", amount: 3, reason: "tool" });
    return false;
  }
  return craftTool(st, "stone", "pickaxe");
}
