/** AutoNPC v4.0 — worker entity yardımcıları. */
import { world } from "@minecraft/server";
import { WORKER_ID, TAG_WORKER, VERSION } from "../core/config.js";
import { say } from "../core/log.js";
import { floorV, dist } from "../core/math.js";
import { loadState, saveState } from "../core/persist.js";
import { addInv, invText } from "../core/state.js";
import { pickName, angry } from "../chat/personality.js";

export function isWorker(e) { return !!e && e.typeId === WORKER_ID; }

export function allWorkers() {
  const out = [];
  for (const d of ["overworld", "nether", "the_end"]) {
    try { for (const e of world.getDimension(d).getEntities({ type: WORKER_ID })) out.push(e); }
    catch (e) { /* boyut yüklü değil */ }
  }
  return out;
}

export function nearestWorker(player, max = 96) {
  let best, bd = max;
  for (const w of allWorkers()) {
    try {
      if (w.dimension.id !== player.dimension.id) continue;
      const d = dist(w.location, player.location);
      if (d < bd) { best = w; bd = d; }
    } catch (e) { /* entity geçersiz */ }
  }
  return best;
}

export function updateName(worker, st) {
  try { worker.nameTag = `§6${st.npcName ?? "AutoNPC"}§r §8${VERSION}§r\n§7${st.status}`; } catch (e) { /* geçersiz */ }
}

export function spawnWorker(player) {
  try {
    const loc = { x: player.location.x + 1.5, y: player.location.y, z: player.location.z + 1.5 };
    const w = player.dimension.spawnEntity(WORKER_ID, loc);
    try { w.addTag(TAG_WORKER); } catch (e) { /* opsiyonel */ }
    const st = loadState(w);
    st.owner = player.name;
    st.npcName = pickName();   // v5.2: rastgele karakter ismi
    st._wid = w.id;
    st.base = floorV(player.location);
    st.status = "Doğdu; emir bekliyor";
    addInv(st, "minecraft:stick", 2);
    saveState(w, st);
    updateName(w, st);
    angry(st, "spawn");
    say(player, `${st.npcName} göreve hazır. Etkileşim = panel; chat: npc yardım`);
    return w;
  } catch (e) {
    say(player, `İşçi oluşturulamadı: ${e}`);
    return undefined;
  }
}

export function stateSummary(worker) {
  const st = loadState(worker);
  return [
    `Durum: ${st.status}`,
    `Mod: ${st.auto ? "Otomatik" : "Emir"}`,
    `Base: ${st.base.x} ${st.base.y} ${st.base.z}`,
    `Görev: ${st.task?.type ?? "yok"} | Kuyruk: ${st.taskQueue.length}`,
    `Elinde: ${(st.held || "minecraft:air").replace("minecraft:", "")}`,
    `Skill: kazı ${st.skills.mining} | odun ${st.skills.woodcutting} | inşaat ${st.skills.building} | craft ${st.skills.crafting}`,
    "",
    "Envanter:",
    invText(st),
  ].join("\n");
}
