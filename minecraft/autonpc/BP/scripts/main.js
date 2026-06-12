/**
 * AutoNPC v5.0.1 — giriş noktası.
 * KÖK DÜZELTME: startTick HER ŞEYDEN ÖNCE ve korumalı. Olay kablolaması
 * (bazı before-event'ler stabil API'de yok → fırlatabilir) tick'i ASLA
 * öldüremez. v4/v5.0'daki "NPC tamamen cansız" hatasının nedeni buydu:
 * registerEvents içindeki korumasız chatSend subscribe'ı tüm init'i kesiyordu.
 */
import { world, system } from "@minecraft/server";
import { VERSION } from "./core/config.js";
import { registerEvents, diagReport } from "./sys/events.js";
import { startTick } from "./sys/tick.js";

let bootError = "";
try { startTick(); } catch (e) { bootError = `tick: ${e}`; }
try { registerEvents(); } catch (e) { bootError += ` events: ${e}`; }

system.runTimeout(() => {
  try {
    for (const p of world.getAllPlayers()) {
      p.sendMessage(`§b[AutoNPC]§r ${VERSION} yüklendi. ${bootError ? "§cBoot uyarısı: " + bootError : ""}`);
      const bad = diagReport().filter((d) => !d.ok);
      if (bad.length) p.sendMessage(`§7[tanı] pasif olaylar: ${bad.map((d) => d.name).join(", ")} (npc tanı)`);
    }
  } catch (e) { /* dünya hazır değilse sessiz */ }
}, 20);
