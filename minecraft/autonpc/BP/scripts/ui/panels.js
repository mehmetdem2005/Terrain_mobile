/**
 * AutoNPC v4.0 — form panelleri. (D8 düzeltmesi)
 * Tüm form gösterimleri tek `show` kapısından: hata mesajı yutulmaz,
 * "UserBusy" durumunda kullanıcı bilgilendirilir.
 */
import { system, ItemStack } from "@minecraft/server";
import { ActionFormData, MessageFormData, ModalFormData } from "@minecraft/server-ui";
import { VERSION, GUIDE_NAME } from "../core/config.js";
import { TREE_TYPES, ORES, COMMON_BLOCKS } from "../core/registry.js";
import { say } from "../core/log.js";
import { spawnWorker, nearestWorker, stateSummary, updateName } from "../sys/workers.js";
import { loadState, saveState } from "../core/persist.js";
import { setTask, stopAll, addInv, removeInv, invText } from "../core/state.js";
import { giveGuide } from "./guide.js";
import { canonicalBlockId } from "../jobs/collect_block.js";
import { floorV } from "../core/math.js";

function show(player, form, cb) {
  system.run(() => {
    form.show(player).then((r) => {
      if (r.cancelationReason === "UserBusy") { say(player, "Başka bir ekran açık; sohbeti/ekranı kapatıp tekrar dene."); return; }
      cb(r);
    }).catch((e) => say(player, `Panel hatası: ${e}`));
  });
}

function playerInv(player) {
  try { return player.getComponent("minecraft:inventory")?.container; } catch (e) { return undefined; }
}
function takeOneHeld(player) {
  try {
    const inv = playerInv(player);
    if (!inv) return undefined;
    const slot = player.selectedSlotIndex ?? 0;
    const stack = inv.getItem(slot);
    if (!stack) return undefined;
    const out = { typeId: stack.typeId };
    if (stack.amount <= 1) inv.setItem(slot, undefined);
    else { stack.amount -= 1; inv.setItem(slot, stack); }
    return out;
  } catch (e) { return undefined; }
}

export function openGuide(player) {
  const w = nearestWorker(player, 96);
  const form = new ActionFormData()
    .title(`§lAutoNPC ${VERSION}`)
    .body(`RealWork: NPC yürür, kırma süresi bekler, doğal drop'u yerden toplar.\nYakın işçi: ${w ? "var" : "yok"}`)
    .button("➕ İşçi oluştur")
    .button(w ? "🤖 İşçi paneli" : "🤖 (yakında işçi yok)")
    .button("📘 Kılavuz")
    .button("📖 Kitabı tekrar ver");
  show(player, form, (r) => {
    if (r.canceled) return;
    if (r.selection === 0) return void spawnWorker(player);
    if (r.selection === 1) { const nw = nearestWorker(player, 96); return nw ? openWorkerPanel(player, nw) : say(player, "Yakında işçi yok."); }
    if (r.selection === 2) return manual(player);
    if (r.selection === 3) return void giveGuide(player, true);
  });
}

function manual(player) {
  const body = [
    "1) Kitaptan işçi oluştur.",
    "2) İşçiye etkileşim = Görev Paneli.",
    "3) Chat yedeği: npc işçi | npc panel | npc odun [tür] [adet] | npc blok <id> <adet> | npc demir | npc oto | npc dur",
    "",
    "v4.0: kalıcı hafıza (dünya kapansa da envanter/görev durur), gerçek A* yürüyüş, alet-drop kuralları.",
  ].join("\n");
  show(player, new MessageFormData().title(`Kılavuz ${VERSION}`).body(body).button1("Kapat").button2("Ana menü"),
    (r) => { if (!r.canceled && r.selection === 1) openGuide(player); });
}

export function openWorkerPanel(player, worker) {
  const st = loadState(worker);
  updateName(worker, st);
  const form = new ActionFormData()
    .title(`§lGörev Paneli ${VERSION}`)
    .body(stateSummary(worker))
    .button("📦 Eldeki 1 eşyayı ver")
    .button("🎒 NPC envanteri")
    .button("🌳 Odun görevi")
    .button("🧱 Blok topla")
    .button("⛏️ Maden")
    .button("🏠 Ev yap")
    .button(st.auto ? "🟢 Otomatik kapat" : "⚪ Otomatik aç")
    .button("🚶 Yürüme testi")
    .button("📍 Base'i buraya al")
    .button("🛑 Durdur");
  show(player, form, (r) => {
    if (r.canceled) return;
    switch (r.selection) {
      case 0: {
        const one = takeOneHeld(player);
        if (!one) say(player, "Elinde eşya yok.");
        else { addInv(st, one.typeId, 1); saveState(worker, st); say(player, `NPC aldı: ${one.typeId} x1`); }
        return openWorkerPanel(player, worker);
      }
      case 1: return inventoryPanel(player, worker);
      case 2: return treeMenu(player, worker);
      case 3: return blockMenu(player, worker);
      case 4: return oreMenu(player, worker);
      case 5: st.auto = false; setTask(st, "build_house", {}); saveState(worker, st); say(player, "Ev görevi verildi."); return;
      case 6: st.auto = !st.auto; st.task = undefined; st.status = st.auto ? "Otomatik mod" : "Emir bekliyor"; st.dirty = true; saveState(worker, st); say(player, `Otomatik: ${st.auto ? "açık" : "kapalı"}`); return;
      case 7: st.auto = false; setTask(st, "walk_test", { target: { x: player.location.x + 6, y: player.location.y, z: player.location.z + 6 } }); saveState(worker, st); say(player, "Yürüme testi verildi."); return;
      case 8: st.base = floorV(player.location); st.dirty = true; saveState(worker, st); say(player, "Base ayarlandı."); return;
      case 9: stopAll(st); saveState(worker, st); updateName(worker, st); say(player, "Durduruldu."); return;
    }
  });
}

function inventoryPanel(player, worker) {
  const st = loadState(worker);
  const entries = Object.entries(st.inventory).filter(([, v]) => v > 0);
  const form = new ActionFormData().title("NPC envanteri").body(invText(st, 40));
  for (const [id, n] of entries) form.button(`Al: ${id.replace("minecraft:", "")} x${n}`);
  form.button("⬅ Geri");
  show(player, form, (r) => {
    if (r.canceled) return;
    if (r.selection >= entries.length) return openWorkerPanel(player, worker);
    const [id] = entries[r.selection];
    if (removeInv(st, id, 1)) {
      if (giveToPlayer(player, id)) say(player, `${id.replace("minecraft:", "")} x1 aldın.`);
      else { addInv(st, id, 1); say(player, "Envanterin dolu."); }
      saveState(worker, st);
    }
    return inventoryPanel(player, worker);
  });
}

function giveToPlayer(player, id) {
  try {
    const inv = playerInv(player);
    if (!inv) return false;
    const left = inv.addItem(new ItemStack(id, 1));
    return !left || left.amount === 0;
  } catch (e) { return false; }
}

function treeMenu(player, worker) {
  const keys = Object.keys(TREE_TYPES);
  const form = new ActionFormData().title("Hangi ağaç?").body("Tür seç; sonra elma/yaprak sorulur.");
  for (const k of keys) form.button(TREE_TYPES[k].label);
  form.button("⬅ Geri");
  show(player, form, (r) => {
    if (r.canceled) return;
    if (r.selection >= keys.length) return openWorkerPanel(player, worker);
    askApple(player, worker, keys[r.selection]);
  });
}

function askApple(player, worker, tree) {
  const form = new MessageFormData().title("Elma / yaprak?")
    .body("Yapraklar da kırılsın mı? (elma şansı)").button1("Hayır, sadece odun").button2("Evet, elma da");
  show(player, form, (r) => {
    if (r.canceled) return;
    const st = loadState(worker);
    st.auto = false;
    setTask(st, "gather_wood", { tree, amount: 64, apples: r.selection === 1 });
    saveState(worker, st);
    say(player, `${TREE_TYPES[tree].label}: ${r.selection === 1 ? "odun + elma" : "sadece odun"}.`);
  });
}

function blockMenu(player, worker) {
  const form = new ActionFormData().title("Blok toplama").body("Hazır seç veya özel ID yaz.");
  for (const [, label] of COMMON_BLOCKS) form.button(label);
  form.button("✍ Özel blok ID");
  form.button("⬅ Geri");
  show(player, form, (r) => {
    if (r.canceled) return;
    if (r.selection === COMMON_BLOCKS.length + 1) return openWorkerPanel(player, worker);
    if (r.selection === COMMON_BLOCKS.length) return customBlock(player, worker);
    const [id] = COMMON_BLOCKS[r.selection];
    const st = loadState(worker);
    st.auto = false;
    setTask(st, "collect_block", { blockId: id, amount: 32 });
    saveState(worker, st);
    say(player, `Blok görevi: ${id} x32`);
  });
}

function customBlock(player, worker) {
  const form = new ModalFormData().title("Özel blok")
    .textField("Blok ID", "minecraft:sand")
    .textField("Miktar", "32");
  show(player, form, (r) => {
    if (r.canceled) return;
    const id = canonicalBlockId(String(r.formValues?.[0] ?? ""));
    const amount = Number(r.formValues?.[1]) || 32;
    if (!id) return say(player, "Geçersiz blok ID.");
    const st = loadState(worker);
    st.auto = false;
    setTask(st, "collect_block", { blockId: id, amount });
    saveState(worker, st);
    say(player, `Blok görevi: ${id} x${amount}`);
  });
}

function oreMenu(player, worker) {
  const keys = Object.keys(ORES);
  const form = new ActionFormData().title("Maden isteği").body("Cevher seç.");
  for (const k of keys) form.button(ORES[k].label);
  form.button("Hepsini kuyruğa ekle");
  form.button("⬅ Geri");
  show(player, form, (r) => {
    if (r.canceled) return;
    const st = loadState(worker);
    st.auto = false;
    if (r.selection >= keys.length + 1) return openWorkerPanel(player, worker);
    if (r.selection === keys.length) {
      for (const k of keys) st.taskQueue.push({ type: "mine_ore", data: { group: k, amount: 8 } });
      st.task = undefined;
      st.dirty = true;
      saveState(worker, st);
      say(player, "Tüm madenler kuyruğa eklendi.");
      return;
    }
    setTask(st, "mine_ore", { group: keys[r.selection], amount: 16 });
    saveState(worker, st);
    say(player, `${ORES[keys[r.selection]].label} görevi verildi.`);
  });
}
