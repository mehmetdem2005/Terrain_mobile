/** AutoNPC v4.0 — giriş noktası. */
import { world, system } from "@minecraft/server";
import { VERSION } from "./core/config.js";
import { registerEvents } from "./sys/events.js";
import { startTick } from "./sys/tick.js";

registerEvents();
startTick();

system.runTimeout(() => {
  try {
    for (const p of world.getAllPlayers()) {
      p.sendMessage(`§b[AutoNPC]§r ${VERSION} yüklendi. Kitap gelmezse: npc kitap`);
    }
  } catch (e) { /* dünya hazır değilse sessiz */ }
}, 20);
