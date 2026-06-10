/** AutoNPC v4.0 — yönetim kitabı verme/teşhis. */
import { ItemStack, system } from "@minecraft/server";
import { GUIDE_ID, GUIDE_NAME } from "../core/config.js";
import { say } from "../core/log.js";

function playerInv(player) {
  try { return player.getComponent("minecraft:inventory")?.container; } catch (e) { return undefined; }
}

export function isGuide(stack) {
  if (!stack) return false;
  if (stack.typeId === GUIDE_ID) return true;
  // custom item yüklenemezse yedek: AutoNPC adlı vanilla kitap
  if (stack.typeId === "minecraft:book" && String(stack.nameTag || "").includes("AutoNPC")) return true;
  return false;
}

function hasGuide(player) {
  const inv = playerInv(player);
  if (!inv) return false;
  for (let i = 0; i < inv.size; i++) if (isGuide(inv.getItem(i))) return true;
  return false;
}

function fallbackBook() {
  const s = new ItemStack("minecraft:book", 1);
  try { s.nameTag = GUIDE_NAME; } catch (e) { /* opsiyonel */ }
  try { s.setLore(["AutoNPC v4.0", "Kullan: panel açılır. Chat: npc yardım"]); } catch (e) { /* opsiyonel */ }
  return s;
}

export function giveGuide(player, force = false) {
  const inv = playerInv(player);
  if (!inv) { say(player, "Envanter okunamadı."); return false; }
  if (!force && hasGuide(player)) return true;
  let ok = false;
  try { ok = !inv.addItem(new ItemStack(GUIDE_ID, 1)); } catch (e) { ok = false; }
  if (!ok) {
    try { const left = inv.addItem(fallbackBook()); ok = !left || left.amount === 0; } catch (e) { ok = false; }
  }
  say(player, ok ? `${GUIDE_NAME} verildi.` : "Kitap verilemedi (envanter dolu?). Chat: npc");
  return ok;
}

export function ensureGuideOnSpawn(player) {
  system.runTimeout(() => {
    try { if (!hasGuide(player)) giveGuide(player, true); } catch (e) { /* oyuncu çıktı */ }
  }, 40);
}
