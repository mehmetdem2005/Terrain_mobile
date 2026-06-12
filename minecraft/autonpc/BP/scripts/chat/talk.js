/**
 * AutoNPC v5.0 — kural tabanlı TR sohbet (durum/envanter farkındalıklı).
 * Yakındaki (12 blok) işçi, "npc" ile başlamayan mesajlara da selam/soru
 * kalıplarında cevap verir.
 */
import { nearestWorker } from "../sys/workers.js";
import { loadState } from "../core/persist.js";
import { invText, countInv } from "../core/state.js";
import { broadcast } from "../core/log.js";
import { dist } from "../core/math.js";

function reply(worker, msg) {
  broadcast(`§e<İşçi>§r ${msg}`);
}

const RULES = [
  { re: /(selam|merhaba|hello|hi|sa)\b/, f: (st) => `Selam! Şu an: ${st.status}` },
  { re: /(nasılsın|naber|nasilsin)/, f: (st) => st.task ? `İyiyim, çalışıyorum: ${st.task.type}` : "İyiyim, emir bekliyorum." },
  { re: /(ne yapıyorsun|napıyorsun|napiyorsun|ne is)/, f: (st) => `${st.status}. Kuyrukta ${st.taskQueue.length} görev var.` },
  { re: /(envanter|çanta|neyin var)/, f: (st) => `Çantamda: ${invText(st, 8).replace(/\n/g, ", ")}` },
  { re: /(elmas)/, f: (st) => `Elmas: ${countInv(st, "minecraft:diamond")} adet.` },
  { re: /(demir)/, f: (st) => `Demir: ingot ${countInv(st, "minecraft:iron_ingot")} + ham ${countInv(st, "minecraft:raw_iron")}.` },
  { re: /(teşekkür|tesekkur|sağol|sagol|eyv)/, f: () => "Rica ederim! İş başına." },
  { re: /(yorgun|dinlen)/, f: () => "Ben yorulmam; görev varsa yaparım." },
  { re: /(kimsin|adın ne|adin ne)/, f: (st) => `AutoNPC ${st.version} işçisiyim. Sahibim: ${st.owner || "henüz yok"}.` },
  { re: /(yardım|komut)/, f: () => "Komutlar: npc yardım yaz. Panel için bana dokun." },
];

/** @returns true → mesaj cevaplandı */
export function tryTalk(player, message) {
  const w = nearestWorker(player, 12);
  if (!w) return false;
  try { if (dist(w.location, player.location) > 12) return false; } catch (e) { return false; }
  const st = loadState(w);
  const msg = String(message || "").toLowerCase();
  for (const r of RULES) {
    if (r.re.test(msg)) { reply(w, r.f(st)); return true; }
  }
  return false;
}
