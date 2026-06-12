/**
 * AutoNPC v5.0.1 — KORUMALI olay kablolaması + tanı ağı.
 * KÖK DÜZELTME: her subscribe bağımsız `sub()` zarfında. Bir olayın stabil
 * API'de olmaması (örn. chatSend before-event'i beta-gated) DİĞERLERİNİ ve
 * tick'i etkileyemez. Hangi olayın bağlandığı `npc tanı` ile görülebilir.
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

const diag = []; // {name, ok, err}
export function diagReport() { return diag; }

function sub(name, fn) {
  try {
    fn();
    diag.push({ name, ok: true });
  } catch (e) {
    diag.push({ name, ok: false, err: String(e).slice(0, 80) });
    try { console.warn(`[AutoNPC] olay bağlanamadı: ${name}: ${e}`); } catch (e2) { /* log yok */ }
  }
}

const lastPanelTick = new Map();
function debounced(player) {
  const now = system.currentTick;
  const last = lastPanelTick.get(player.id) ?? -999;
  if (now - last < PANEL_DEBOUNCE) return true;
  lastPanelTick.set(player.id, now);
  return false;
}

export function registerEvents() {
  sub("playerSpawn", () => world.afterEvents.playerSpawn.subscribe((ev) => {
    if (ev.initialSpawn && ev.player) ensureGuideOnSpawn(ev.player);
  }));

  // kitap kullanımı → ana menü (panele HER ZAMAN ulaşılabilen yol)
  sub("itemUse", () => world.afterEvents.itemUse.subscribe((ev) => {
    if (!ev.source || !isGuide(ev.itemStack)) return;
    if (debounced(ev.source)) return;
    openGuide(ev.source);
  }));

  // işçiyle etkileşim → panel
  sub("interactWithEntity", () => world.beforeEvents.playerInteractWithEntity.subscribe((ev) => {
    if (ev.target?.typeId !== WORKER_ID || !ev.player) return;
    ev.cancel = true;
    const player = ev.player, target = ev.target;
    system.run(() => {
      if (debounced(player)) return;
      openWorkerPanel(player, target);
    });
  }));

  // scriptevent köprüsü — chat'siz cihazlarda da TÜM komutlar çalışsın:
  // /scriptevent autonpc:cmd <npc komutu>  (örn: /scriptevent autonpc:cmd odun oak 16)
  sub("scriptEventReceive", () => system.afterEvents.scriptEventReceive.subscribe((ev) => {
    const p = ev.sourceEntity?.typeId === "minecraft:player" ? ev.sourceEntity : world.getAllPlayers()[0];
    if (!p) return;
    if (ev.id === "autonpc:give_book") giveGuide(p, true);
    else if (ev.id === "autonpc:spawn_worker") spawnWorker(p);
    else if (ev.id === "autonpc:panel") openGuide(p);
    else if (ev.id === "autonpc:cmd") handleChat(p, "npc " + String(ev.message || "yardım"));
  }));

  // chat komutları + sohbet — STABIL API'DE OLMAYABİLİR (beta-gated).
  // Bağlanamazsa tanıya düşer; komutlar scriptevent + panel ile yine tam çalışır.
  sub("chatSend", () => world.beforeEvents.chatSend.subscribe((ev) => {
    if (handleChat(ev.sender, ev.message)) { ev.cancel = true; return; }
    const sender = ev.sender, msg = ev.message;
    system.run(() => { try { tryTalk(sender, msg); } catch (e) { /* sohbet opsiyonel */ } });
  }));

  // alan seçimi (kendi içinde de korumalı)
  sub("selectionWand", () => registerSelection());

  // zırh + kalkan hasar azaltımı
  sub("entityHurt", () => world.afterEvents.entityHurt.subscribe((ev) => {
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
  }));
}
