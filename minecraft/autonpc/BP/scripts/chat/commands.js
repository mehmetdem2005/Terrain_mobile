/** AutoNPC v4.0 — "npc ..." chat komutları (TR/EN takma adlar). */
import { VERSION } from "../core/config.js";
import { ORES } from "../core/registry.js";
import { say } from "../core/log.js";
import { giveGuide } from "../ui/guide.js";
import { openGuide, openWorkerPanel } from "../ui/panels.js";
import { spawnWorker, nearestWorker, stateSummary } from "../sys/workers.js";
import { loadState, saveState } from "../core/persist.js";
import { setTask, stopAll } from "../core/state.js";
import { canonicalBlockId } from "../jobs/collect_block.js";

const TREE_ALIASES = {
  mese: "oak", "meşe": "oak", oak: "oak",
  hus: "birch", "huş": "birch", birch: "birch",
  ladin: "spruce", spruce: "spruce",
  orman: "jungle", jungle: "jungle",
  akasya: "acacia", acacia: "acacia",
  koyu_mese: "dark_oak", koyumese: "dark_oak", dark_oak: "dark_oak", darkoak: "dark_oak",
  mangrov: "mangrove", mangrove: "mangrove",
  kiraz: "cherry", cherry: "cherry",
  any: "any", hepsi: "any",
};

function parseTree(raw) {
  const x = String(raw || "any").toLowerCase()
    .replace(/ı/g, "i").replace(/ş/g, "s").replace(/ğ/g, "g")
    .replace(/ü/g, "u").replace(/ö/g, "o").replace(/ç/g, "c").replace(/ /g, "_");
  return TREE_ALIASES[x] ?? TREE_ALIASES[raw] ?? "any";
}

const HELP = `${VERSION}: npc kitap | npc işçi | npc panel | npc odun [ağaç] [adet] [elma] | npc blok <id> <adet> | npc demir | npc elmas | npc ev | npc yürü | npc oto | npc durum | npc dur`;

/** @returns true → mesaj tüketildi (chat'e düşmesin) */
export function handleChat(player, message) {
  const msg = String(message || "").trim().toLowerCase();
  if (!(msg === "npc" || msg.startsWith("npc "))) return false;
  const parts = msg.split(/\s+/g);
  const cmd = parts[1] || "yardım";

  if (["yardım", "yardim", "help", "?"].includes(cmd)) { say(player, HELP); return true; }
  if (["kitap", "book"].includes(cmd)) { giveGuide(player, true); return true; }
  if (["işçi", "isci", "worker", "spawn"].includes(cmd)) { spawnWorker(player); return true; }
  if (["panel", "menu", "menü"].includes(cmd)) {
    const w = nearestWorker(player, 96);
    w ? openWorkerPanel(player, w) : openGuide(player);
    return true;
  }

  const w = nearestWorker(player, 96);
  if (!w) { say(player, "Yakında işçi yok. 'npc işçi' yaz."); return true; }
  const st = loadState(w);
  const done = () => { saveState(w, st); return true; };

  if (["durum", "status"].includes(cmd)) { say(player, stateSummary(w).replace(/\n/g, " | ")); return true; }
  if (["dur", "stop"].includes(cmd)) { stopAll(st); say(player, "Durduruldu."); return done(); }
  if (["oto", "auto"].includes(cmd)) {
    st.auto = !st.auto; st.task = undefined; st.dirty = true;
    st.status = st.auto ? "Otomatik mod" : "Emir bekliyor";
    say(player, `Otomatik: ${st.auto ? "açık" : "kapalı"}`);
    return done();
  }
  if (["yürü", "yuru", "walk"].includes(cmd)) {
    setTask(st, "walk_test", { target: { x: player.location.x + 6, y: player.location.y, z: player.location.z + 6 } });
    say(player, "Yürüme testi verildi.");
    return done();
  }
  if (["odun", "wood", "ağaç", "agac"].includes(cmd)) {
    const tree = parseTree(parts[2]);
    const amount = Number(parts[3]) || 64;
    const apples = parts.includes("elma") || parts.includes("apple");
    setTask(st, "gather_wood", { tree, amount, apples });
    say(player, `Odun: ${tree} x${amount}${apples ? " + elma" : ""}`);
    return done();
  }
  if (["elma", "apple"].includes(cmd)) {
    setTask(st, "gather_wood", { tree: "oak", amount: 16, apples: true });
    say(player, "Elma görevi verildi.");
    return done();
  }
  if (["blok", "block", "topla"].includes(cmd)) {
    const id = canonicalBlockId(parts[2] || "stone");
    const amount = Number(parts[3]) || 32;
    setTask(st, "collect_block", { blockId: id, amount });
    say(player, `Blok: ${id} x${amount}`);
    return done();
  }
  if (ORES[cmd]) {
    setTask(st, "mine_ore", { group: cmd, amount: Number(parts[2]) || 16 });
    say(player, `${ORES[cmd].label} görevi verildi.`);
    return done();
  }
  if (["demir", "iron"].includes(cmd)) { setTask(st, "mine_ore", { group: "iron", amount: Number(parts[2]) || 16 }); say(player, "Demir görevi."); return done(); }
  if (["elmas", "diamond"].includes(cmd)) { setTask(st, "mine_ore", { group: "diamond", amount: Number(parts[2]) || 8 }); say(player, "Elmas görevi."); return done(); }
  if (["ev", "house"].includes(cmd)) { setTask(st, "build_house", {}); say(player, "Ev görevi."); return done(); }

  say(player, "Komut anlaşılmadı. npc yardım");
  return true;
}
