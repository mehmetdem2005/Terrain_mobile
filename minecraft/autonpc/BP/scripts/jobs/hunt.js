/**
 * AutoNPC v5.0 — hayvan avı. Hedefe yürür, kılıçla vurur (gerçek hasar),
 * ölünce GERÇEK loot düşer ve toplanır.
 */
import { finishTask } from "../core/state.js";
import { walkTo } from "../nav/locomotion.js";
import { meleeAttack } from "../combat/attack.js";
import { dist, floorV } from "../core/math.js";
import { itemStackOf } from "../sys/blocks.js";
import { addInv } from "../core/state.js";
import { isToolItem } from "../core/registry.js";
import { equipMainhand } from "../sys/equipment.js";

export const ANIMALS = {
  any: ["minecraft:cow", "minecraft:sheep", "minecraft:pig", "minecraft:chicken", "minecraft:llama", "minecraft:horse", "minecraft:rabbit"],
  inek: ["minecraft:cow"], cow: ["minecraft:cow"],
  koyun: ["minecraft:sheep"], sheep: ["minecraft:sheep"],
  domuz: ["minecraft:pig"], pig: ["minecraft:pig"],
  tavuk: ["minecraft:chicken"], chicken: ["minecraft:chicken"],
  lama: ["minecraft:llama"], llama: ["minecraft:llama"],
  at: ["minecraft:horse"], horse: ["minecraft:horse"],
};

function findAnimal(worker, types, radius = 24) {
  let best, bd = radius;
  try {
    for (const e of worker.dimension.getEntities({ location: worker.location, maxDistance: radius })) {
      if (!types.includes(e.typeId)) continue;
      const d = dist(e.location, worker.location);
      if (d < bd) { best = e; bd = d; }
    }
  } catch (e) { /* boyut */ }
  return best;
}

function collectGroundItems(worker, st, origin, radius = 4) {
  try {
    const ents = worker.dimension.getEntities({ type: "minecraft:item", location: origin, maxDistance: radius });
    if (!ents.length) return false;
    const e = ents[0];
    if (dist(e.location, worker.location) > 1.4) {
      walkTo(worker, floorV(e.location), { reach: 0, arrive: 1.3, speed: 0.18 });
      return true;
    }
    const s = itemStackOf(e) || { typeId: "minecraft:leather", amount: 1 };
    try { e.remove(); } catch (err) { /* kapıldı */ }
    addInv(st, s.typeId, s.amount || 1);
    if (!isToolItem(st.held)) equipMainhand(worker, st, s.typeId);
    st.status = `Topladı: ${s.typeId.replace("minecraft:", "")}`;
    return true;
  } catch (e) { return false; }
}

export function tickHunt(worker, st, data) {
  const types = ANIMALS[data.animal || "any"] || ANIMALS.any;
  data.kills = data.kills ?? 0;
  const want = data.amount ?? 3;

  // önce yerdeki ganimet
  if (data.lootAt && collectGroundItems(worker, st, data.lootAt)) return;
  if (data.lootAt) { data.lootAt = undefined; st.dirty = true; }

  if (data.kills >= want) return finishTask(st, `Av tamam: ${data.kills} hayvan`);

  const target = findAnimal(worker, types);
  if (!target) { st.status = "Av hayvanı aranıyor (yakında yok)"; return; }
  const d = dist(target.location, worker.location);
  if (d > 2.6) {
    st.status = `Ava yürüyor: ${target.typeId.replace("minecraft:", "")}`;
    const r = walkTo(worker, floorV(target.location), { reach: 2 });
    if (r.blocked) st.status = "Ava yol yok; bekliyor";
    return;
  }
  meleeAttack(worker, st, target);
  st.status = `Avlıyor: ${target.typeId.replace("minecraft:", "")}`;
  // öldü mü? (geçersiz veya can <= 0)
  try {
    const hp = target.getComponent("minecraft:health");
    if (!hp || hp.currentValue <= 0) {
      data.kills++;
      data.lootAt = { x: target.location.x, y: target.location.y, z: target.location.z };
      st.dirty = true;
    }
  } catch (e) {
    data.kills++;
    data.lootAt = { x: worker.location.x, y: worker.location.y, z: worker.location.z };
    st.dirty = true;
  }
}
