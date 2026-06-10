/**
 * AutoNPC v4.0 — olay kablolaması. (D4 düzeltmesi)
 * v3 aynı etkileşim için before+after+dataDriven üçlü abone olup paneli
 * 2-3 kez açıyordu; scriptEventReceive'i de yanlış kaynaktan (world) dinliyordu.
 * v4: her niyet için TEK abonelik + oyuncu-başına debounce.
 */
import { world, system } from "@minecraft/server";
import { WORKER_ID, PANEL_DEBOUNCE } from "../core/config.js";
import { isGuide, giveGuide, ensureGuideOnSpawn } from "../ui/guide.js";
import { openGuide, openWorkerPanel } from "../ui/panels.js";
import { spawnWorker } from "./workers.js";
import { handleChat } from "../chat/commands.js";
import { tryTalk } from "../chat/talk.js";
import { registerSelection } from "./selection.js";
import { loadState } from "../core/persist.js";
import { armorPoints } from "../combat/gear.js";
import { shieldWindows } from "../combat/threats.js";

const lastPanelTick = new Map(); // playerId -> system.currentTick

function debounced(player) {
  const now = system.currentTick;
  const last = lastPanelTick.get(player.id) ?? -999;
  if (now - last < PANEL_DEBOUNCE) return true;
  lastPanelTick.set(player.id, now);
  return false;
}

export function registerEvents() {
  // yeni oyuncuya kitap
  world.afterEvents.playerSpawn.subscribe((ev) => {
    if (ev.initialSpawn && ev.player) ensureGuideOnSpawn(ev.player);
  });

  // kitap kullanımı → ana menü (TEK abonelik: after)
  world.afterEvents.itemUse.subscribe((ev) => {
    if (!ev.source || !isGuide(ev.itemStack)) return;
    if (debounced(ev.source)) return;
    openGuide(ev.source);
  });

  // işçiyle etkileşim → panel (TEK abonelik: before + system.run)
  world.beforeEvents.playerInteractWithEntity.subscribe((ev) => {
    if (ev.target?.typeId !== WORKER_ID || !ev.player) return;
    ev.cancel = true;
    const player = ev.player, target = ev.target;
    system.run(() => {
      if (debounced(player)) return;
      openWorkerPanel(player, target);
    });
  });

  // scriptevent köprüsü (mcfunction'lar için) — DOĞRU kaynak: system.afterEvents
  system.afterEvents.scriptEventReceive.subscribe((ev) => {
    const p = ev.sourceEntity?.typeId === "minecraft:player" ? ev.sourceEntity : world.getAllPlayers()[0];
    if (!p) return;
    if (ev.id === "autonpc:give_book") giveGuide(p, true);
    if (ev.id === "autonpc:spawn_worker") spawnWorker(p);
    if (ev.id === "autonpc:panel") openGuide(p);
  });

  // chat komutları + serbest sohbet
  world.beforeEvents.chatSend.subscribe((ev) => {
    if (handleChat(ev.sender, ev.message)) { ev.cancel = true; return; }
    const sender = ev.sender, msg = ev.message;
    system.run(() => { try { tryTalk(sender, msg); } catch (e) { /* sohbet opsiyonel */ } });
  });

  // v5: alan seçimi (çubuk + hologram)
  registerSelection();

  // v5: zırh + kalkan hasar azaltımı (custom entity'de armor attribute yok —
  // vanilla formüle yakın telafi: zırh puanı*%4, kalkan penceresi +%60)
  world.afterEvents.entityHurt.subscribe((ev) => {
    try {
      const w = ev.hurtEntity;
      if (w?.typeId !== WORKER_ID) return;
      const st = loadState(w);
      let reduce = Math.min(0.8, armorPoints(st) * 0.04);
      const cause = ev.damageSource?.cause ?? "";
      if ((shieldWindows.get(w.id) ?? 0) > 0 && (cause === "entityExplosion" || cause === "blockExplosion" || cause === "projectile" || cause === "entityAttack")) {
        reduce = Math.min(0.95, reduce + 0.6);
        st.status = "Kalkan hasarı emdi!";
      }
      if (reduce <= 0 || ev.damage <= 0) return;
      const hp = w.getComponent("minecraft:health");
      if (!hp) return;
      hp.setCurrentValue(Math.min(hp.effectiveMax, hp.currentValue + ev.damage * reduce));
    } catch (e) { /* telafi opsiyonel */ }
  });
}
