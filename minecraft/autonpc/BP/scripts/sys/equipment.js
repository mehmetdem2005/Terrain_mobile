/**
 * AutoNPC v4.0 — el ekipmanı. (D2 düzeltmesi)
 * v3 `replaceitem` komutunu runCommandAsync ile atıyordu (2.0'da yok).
 * v4 EquippableComponent API'sini kullanır; bileşen yoksa görsel atlanır
 * (sanal envanter yine doğru kalır).
 */
import { EquipmentSlot, ItemStack } from "@minecraft/server";
import { setHeld } from "../core/state.js";

export function equipMainhand(worker, st, itemId) {
  setHeld(st, itemId);
  try {
    const eq = worker.getComponent("minecraft:equippable");
    if (!eq) return false;
    if (!itemId || itemId === "minecraft:air") {
      eq.setEquipment(EquipmentSlot.Mainhand, undefined);
      return true;
    }
    eq.setEquipment(EquipmentSlot.Mainhand, new ItemStack(itemId, 1));
    return true;
  } catch (e) {
    return false; // görsel başarısızlık görev mantığını etkilemez
  }
}
