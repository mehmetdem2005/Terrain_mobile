/** AutoNPC v4.0 — mesaj ve iz kayıtları. */
import { world } from "@minecraft/server";

const PREFIX = "§b[AutoNPC]§r ";

export function say(player, msg) {
  try { player.sendMessage(PREFIX + msg); } catch (e) { /* oyuncu ayrılmış olabilir */ }
}
export function broadcast(msg) {
  try { world.sendMessage(PREFIX + msg); } catch (e) { /* dünya hazır değil */ }
}
/** Worker state'ine kısa iz bırakır (son 16 kayıt). */
export function trace(st, msg) {
  st.trace.push(`${Date.now() % 100000}:${msg}`);
  if (st.trace.length > 16) st.trace.shift();
}
export function traceText(st) {
  return st.trace.slice(-8).join("\n") || "iz yok";
}
