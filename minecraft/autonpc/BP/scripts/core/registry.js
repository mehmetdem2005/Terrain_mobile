/**
 * AutoNPC v4.0 — blok/araç/cevher veri kayıtları. (D9 düzeltmesi)
 * v3'te config+classifier+tool_controller+utils'e dağılmış tabloların TEK kaynağı.
 */

export const LOG_BLOCKS = new Set([
  "minecraft:oak_log", "minecraft:birch_log", "minecraft:spruce_log", "minecraft:jungle_log",
  "minecraft:acacia_log", "minecraft:dark_oak_log", "minecraft:mangrove_log", "minecraft:cherry_log",
  "minecraft:log", "minecraft:log2",
  "minecraft:stripped_oak_log", "minecraft:stripped_birch_log", "minecraft:stripped_spruce_log",
  "minecraft:stripped_jungle_log", "minecraft:stripped_acacia_log", "minecraft:stripped_dark_oak_log",
  "minecraft:stripped_mangrove_log", "minecraft:stripped_cherry_log",
]);

export const LEAF_BLOCKS = new Set([
  "minecraft:oak_leaves", "minecraft:birch_leaves", "minecraft:spruce_leaves", "minecraft:jungle_leaves",
  "minecraft:acacia_leaves", "minecraft:dark_oak_leaves", "minecraft:mangrove_leaves", "minecraft:cherry_leaves",
  "minecraft:azalea_leaves", "minecraft:flowering_azalea_leaves", "minecraft:leaves", "minecraft:leaves2",
]);

export const APPLE_LEAVES = new Set([
  "minecraft:oak_leaves", "minecraft:dark_oak_leaves", "minecraft:leaves", "minecraft:leaves2",
]);

export const TREE_TYPES = {
  any: { label: "Her tür ağaç", logs: [...LOG_BLOCKS], leaves: [...LEAF_BLOCKS] },
  oak: { label: "Meşe", logs: ["minecraft:oak_log", "minecraft:log"], leaves: ["minecraft:oak_leaves", "minecraft:leaves"] },
  birch: { label: "Huş", logs: ["minecraft:birch_log"], leaves: ["minecraft:birch_leaves"] },
  spruce: { label: "Ladin", logs: ["minecraft:spruce_log"], leaves: ["minecraft:spruce_leaves"] },
  jungle: { label: "Orman", logs: ["minecraft:jungle_log"], leaves: ["minecraft:jungle_leaves"] },
  acacia: { label: "Akasya", logs: ["minecraft:acacia_log"], leaves: ["minecraft:acacia_leaves"] },
  dark_oak: { label: "Koyu meşe", logs: ["minecraft:dark_oak_log", "minecraft:log2"], leaves: ["minecraft:dark_oak_leaves", "minecraft:leaves2"] },
  mangrove: { label: "Mangrov", logs: ["minecraft:mangrove_log"], leaves: ["minecraft:mangrove_leaves"] },
  cherry: { label: "Kiraz", logs: ["minecraft:cherry_log"], leaves: ["minecraft:cherry_leaves"] },
};

export const ORES = {
  coal: { label: "Kömür", ores: ["minecraft:coal_ore", "minecraft:deepslate_coal_ore"], drop: "minecraft:coal", tool: "wood" },
  copper: { label: "Bakır", ores: ["minecraft:copper_ore", "minecraft:deepslate_copper_ore"], drop: "minecraft:raw_copper", tool: "stone" },
  iron: { label: "Demir", ores: ["minecraft:iron_ore", "minecraft:deepslate_iron_ore"], drop: "minecraft:raw_iron", tool: "stone" },
  gold: { label: "Altın", ores: ["minecraft:gold_ore", "minecraft:deepslate_gold_ore"], drop: "minecraft:raw_gold", tool: "iron" },
  redstone: { label: "Redstone", ores: ["minecraft:redstone_ore", "minecraft:deepslate_redstone_ore"], drop: "minecraft:redstone", tool: "iron" },
  lapis: { label: "Lapis", ores: ["minecraft:lapis_ore", "minecraft:deepslate_lapis_ore"], drop: "minecraft:lapis_lazuli", tool: "iron" },
  diamond: { label: "Elmas", ores: ["minecraft:diamond_ore", "minecraft:deepslate_diamond_ore"], drop: "minecraft:diamond", tool: "iron" },
  emerald: { label: "Zümrüt", ores: ["minecraft:emerald_ore", "minecraft:deepslate_emerald_ore"], drop: "minecraft:emerald", tool: "iron" },
};

export const STONE_BLOCKS = new Set([
  "minecraft:stone", "minecraft:deepslate", "minecraft:tuff",
  "minecraft:andesite", "minecraft:diorite", "minecraft:granite", "minecraft:cobblestone",
  "minecraft:cobbled_deepslate",
]);

export const DIRT_BLOCKS = new Set([
  "minecraft:dirt", "minecraft:grass_block", "minecraft:coarse_dirt", "minecraft:rooted_dirt",
  "minecraft:sand", "minecraft:gravel", "minecraft:clay", "minecraft:mud", "minecraft:snow",
]);

export const FORBIDDEN = new Set([
  "minecraft:air", "minecraft:cave_air", "minecraft:void_air", "minecraft:bedrock",
  "minecraft:barrier", "minecraft:command_block", "minecraft:chain_command_block",
  "minecraft:repeating_command_block", "minecraft:structure_block", "minecraft:jigsaw",
  "minecraft:end_portal_frame", "minecraft:reinforced_deepslate",
]);

export const AIR = new Set(["minecraft:air", "minecraft:cave_air", "minecraft:void_air"]);
export const LIQUID = new Set(["minecraft:water", "minecraft:flowing_water", "minecraft:lava", "minecraft:flowing_lava"]);
export const HAZARD = new Set(["minecraft:lava", "minecraft:flowing_lava", "minecraft:fire", "minecraft:soul_fire", "minecraft:magma", "minecraft:cactus", "minecraft:sweet_berry_bush", "minecraft:powder_snow"]);
export const PASSABLE_EXTRA = new Set([
  "minecraft:tallgrass", "minecraft:short_grass", "minecraft:fern", "minecraft:large_fern",
  "minecraft:snow_layer", "minecraft:vine", "minecraft:torch", "minecraft:deadbush",
  "minecraft:dandelion", "minecraft:poppy", "minecraft:water", "minecraft:flowing_water",
]);

export const COMMON_BLOCKS = [
  ["minecraft:dirt", "Toprak"], ["minecraft:grass_block", "Çimen bloğu"], ["minecraft:sand", "Kum"],
  ["minecraft:gravel", "Çakıl"], ["minecraft:stone", "Taş"], ["minecraft:deepslate", "Derin taş"],
  ["minecraft:oak_log", "Meşe odunu"], ["minecraft:oak_leaves", "Meşe yaprağı"],
];

export const TOOL_LEVEL = { hand: 0, wood: 1, stone: 2, iron: 3, diamond: 4, netherite: 5 };
export const TOOL_ORDER = ["netherite", "diamond", "iron", "stone", "wood"];

const ORE_BY_BLOCK = new Map();
for (const key of Object.keys(ORES)) for (const id of ORES[key].ores) ORE_BY_BLOCK.set(id, { key, ...ORES[key] });

export function oreInfo(id) { return ORE_BY_BLOCK.get(id); }
export function isAir(id) { return AIR.has(id); }
export function isLiquid(id) { return LIQUID.has(id); }
export function isHazard(id) { return HAZARD.has(id); }
export function isPassable(id) { return AIR.has(id) || PASSABLE_EXTRA.has(id); }
export function isSolid(id) { return !isPassable(id) && !LIQUID.has(id); }
export function isBreakable(id) { return !!id && !FORBIDDEN.has(id) && !LIQUID.has(id); }

// v5: nether/elit bloklar — özel kazı kuralları
export const HARD_BLOCKS = {
  "minecraft:obsidian": { level: "diamond", ticks: { netherite: 90, diamond: 110 }, fallback: 500 },
  "minecraft:ancient_debris": { level: "diamond", ticks: { netherite: 50, diamond: 60 }, fallback: 400 },
  "minecraft:netherrack": { level: "wood", ticks: { netherite: 6, diamond: 7, iron: 9, stone: 12, wood: 16 }, fallback: 40 },
};

/** Bloğun gerektirdiği alet sınıfı. */
export function toolClassFor(id) {
  if (LOG_BLOCKS.has(id)) return "axe";
  if (LEAF_BLOCKS.has(id)) return "hand";
  if (STONE_BLOCKS.has(id) || ORE_BY_BLOCK.has(id) || HARD_BLOCKS[id]) return "pickaxe";
  if (DIRT_BLOCKS.has(id)) return "shovel";
  return "hand";
}

/** Drop için gereken minimum kazı seviyesi ("hand" = elle de düşer). */
export function harvestLevelFor(id) {
  if (HARD_BLOCKS[id]) return HARD_BLOCKS[id].level;
  const ore = ORE_BY_BLOCK.get(id);
  if (ore) return ore.tool;
  if (STONE_BLOCKS.has(id)) return "wood";
  return "hand";
}

/** Bloğun doğal drop'u (oyuncu kuralları, basitleştirilmiş). */
export function dropFor(id) {
  if (id === "minecraft:stone") return "minecraft:cobblestone";
  if (id === "minecraft:deepslate") return "minecraft:cobbled_deepslate";
  if (id === "minecraft:log") return "minecraft:oak_log";
  if (id === "minecraft:log2") return "minecraft:dark_oak_log";
  if (LOG_BLOCKS.has(id)) return id;
  if (LEAF_BLOCKS.has(id)) return "minecraft:air";
  const ore = ORE_BY_BLOCK.get(id);
  if (ore) return ore.drop;
  if (id === "minecraft:grass_block") return "minecraft:dirt";
  if (id === "minecraft:clay") return "minecraft:clay_ball";
  if (id === "minecraft:gravel") return "minecraft:gravel";
  if (id === "minecraft:snow") return "minecraft:snowball";
  return id;
}

/** Eldeki aletin tier'ı. */
export function toolTier(item) {
  const s = String(item || "");
  if (s.includes("netherite_")) return "netherite";
  if (s.includes("diamond_")) return "diamond";
  if (s.includes("iron_")) return "iron";
  if (s.includes("stone_")) return "stone";
  if (s.includes("wooden_") || s.includes("wood_")) return "wood";
  return "hand";
}

export function toolItemId(tier, cls) {
  if (cls !== "axe" && cls !== "pickaxe" && cls !== "shovel") return "minecraft:air";
  return `minecraft:${tier === "wood" ? "wooden" : tier}_${cls}`;
}

/** Kırma süresi (tick). Gerçek oyuncuya yakın, tek tablo. */
export function breakTicks(blockId, heldItem) {
  const cls = toolClassFor(blockId);
  const tier = toolTier(heldItem);
  const right = cls === "hand" || String(heldItem || "").includes(`_${cls}`);
  const hard = HARD_BLOCKS[blockId];
  if (hard) return (right && hard.ticks[tier]) || hard.fallback;
  if (LOG_BLOCKS.has(blockId)) {
    if (!right) return 60;
    return { netherite: 14, diamond: 16, iron: 20, stone: 26, wood: 32 }[tier] ?? 60;
  }
  if (LEAF_BLOCKS.has(blockId)) return 8;
  if (STONE_BLOCKS.has(blockId) || ORE_BY_BLOCK.has(blockId)) {
    if (!right) return 110;
    return { netherite: 22, diamond: 26, iron: 34, stone: 44, wood: 60 }[tier] ?? 110;
  }
  if (cls === "shovel") return right && tier !== "hand" ? 14 : 26;
  return 24;
}

/** Eldeki aletle bu blok drop verir mi? (D9: harvest kuralı artık UYGULANIYOR) */
export function canHarvest(blockId, heldItem) {
  const need = harvestLevelFor(blockId);
  if (need === "hand") return true;
  const cls = toolClassFor(blockId);
  const tier = toolTier(heldItem);
  return String(heldItem || "").includes(`_${cls}`) && (TOOL_LEVEL[tier] ?? 0) >= (TOOL_LEVEL[need] ?? 0);
}

export function isToolItem(item) {
  const s = String(item || "");
  return s.includes("_pickaxe") || s.includes("_axe") || s.includes("_shovel") || s.includes("_sword") || s.includes("_hoe");
}
