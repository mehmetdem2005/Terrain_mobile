/**
 * AutoNPC v5.0 — değnekle alan seçimi + partikül hologram çerçeve.
 * Oyuncu elinde ÇUBUK (stick) ile bloğa kullanınca köşe A, ikinci kullanımda
 * köşe B işaretlenir; seçim aktifken kenarlar endrod partikülüyle çizilir.
 */
import { world, system } from "@minecraft/server";
import { say } from "../core/log.js";

const selections = new Map(); // playerName -> {a, b, dim}

export function getSelection(playerName) {
  const s = selections.get(playerName);
  if (!s || !s.a || !s.b) return undefined;
  return {
    min: { x: Math.min(s.a.x, s.b.x), y: Math.min(s.a.y, s.b.y), z: Math.min(s.a.z, s.b.z) },
    max: { x: Math.max(s.a.x, s.b.x), y: Math.max(s.a.y, s.b.y), z: Math.max(s.a.z, s.b.z) },
    dim: s.dim,
  };
}
export function clearSelection(playerName) { selections.delete(playerName); }

export function registerSelection() {
  world.beforeEvents.playerInteractWithBlock.subscribe((ev) => {
    try {
      if (ev.itemStack?.typeId !== "minecraft:stick" || !ev.player) return;
      ev.cancel = true;
      const p = ev.player, loc = ev.block.location;
      system.run(() => {
        let s = selections.get(p.name);
        if (!s || (s.a && s.b)) { s = { a: { ...loc }, b: undefined, dim: p.dimension.id }; selections.set(p.name, s); say(p, `Köşe A: ${loc.x} ${loc.y} ${loc.z} (çubukla 2. köşeyi işaretle)`); }
        else { s.b = { ...loc }; say(p, `Köşe B: ${loc.x} ${loc.y} ${loc.z} — hologram aktif. Panel/chat: npc düzleştir | npc doldur`); }
      });
    } catch (e) { /* event kapalı olabilir */ }
  });

  // hologram: kenar çizgileri (10 tick'te bir, seçim başına ~yüz nokta)
  system.runInterval(() => {
    for (const [name, s] of selections) {
      if (!s.a || !s.b) continue;
      const player = world.getAllPlayers().find((p) => p.name === name);
      if (!player) { selections.delete(name); continue; }
      const dim = player.dimension;
      if (dim.id !== s.dim) continue;
      const mn = { x: Math.min(s.a.x, s.b.x), y: Math.min(s.a.y, s.b.y), z: Math.min(s.a.z, s.b.z) };
      const mx = { x: Math.max(s.a.x, s.b.x) + 1, y: Math.max(s.a.y, s.b.y) + 1, z: Math.max(s.a.z, s.b.z) + 1 };
      const step = Math.max(1, Math.floor(Math.max(mx.x - mn.x, mx.z - mn.z) / 12));
      const edge = (x, y, z) => { try { dim.spawnParticle("minecraft:endrod", { x, y, z }); } catch (e) { /* uzak chunk */ } };
      for (let x = mn.x; x <= mx.x; x += step) for (const y of [mn.y, mx.y]) for (const z of [mn.z, mx.z]) edge(x, y, z);
      for (let z = mn.z; z <= mx.z; z += step) for (const y of [mn.y, mx.y]) for (const x of [mn.x, mx.x]) edge(x, y, z);
      for (let y = mn.y; y <= mx.y; y += step) for (const x of [mn.x, mx.x]) for (const z of [mn.z, mx.z]) edge(x, y, z);
    }
  }, 10);
}
