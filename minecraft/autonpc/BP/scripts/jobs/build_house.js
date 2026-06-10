/**
 * AutoNPC v5.0 — gerçek ev: zemin + taş duvar + kapı boşluğu + ÜÇGEN ÇATI +
 * iç eşya (2 sandık, craft masası, fırın, yatak, varsa büyü masası).
 * Her blok: malzeme düş → bloğun yanına YÜRÜ → yerleştir (RealWork).
 * Bitince fazla eşyayı sandığa GERÇEK container API'siyle koyar.
 */
import { ItemStack } from "@minecraft/server";
import { countInv, removeInv, finishTask, pushSubTask } from "../core/state.js";
import { craftPlanks } from "../work/tools.js";
import { craft } from "../core/recipes.js";
import { blockIdAt, blockAt, setBlock, playSoundAt } from "../sys/blocks.js";
import { isAir, LOG_BLOCKS, isToolItem } from "../core/registry.js";
import { walkTo, faceBlock } from "../nav/locomotion.js";
import { horizDist } from "../core/math.js";

const NEED_WOOD = 40;
const NEED_STONE = 26;
const PLACE_RANGE = 4.0;
const KEEP_IN_HAND = new Set(["minecraft:bed", "minecraft:bow", "minecraft:arrow", "minecraft:shield", "minecraft:torch", "minecraft:obsidian", "minecraft:flint_and_steel"]);

function totalWood(st) {
  return [...LOG_BLOCKS].reduce((n, id) => n + countInv(st, id), 0) + countInv(st, "minecraft:oak_planks");
}

/** 7x7 taban; taş duvar y1-2; -Z cephesinde kapı; üçgen çatı y3-5. */
function housePlan(base, st) {
  const out = [];
  const W = 3; // yarı genişlik
  for (let x = -W; x <= W; x++) for (let z = -W; z <= W; z++) out.push([base.x + x, base.y, base.z + z, "minecraft:oak_planks"]);
  for (let y = 1; y <= 2; y++) {
    for (let x = -W; x <= W; x++) for (let z = -W; z <= W; z++) {
      if (Math.abs(x) !== W && Math.abs(z) !== W) continue;
      if (z === -W && x === 0) continue; // kapı boşluğu
      out.push([base.x + x, base.y + y, base.z + z, "minecraft:cobblestone"]);
    }
  }
  // üçgen çatı: her katta daralan plank halkası + mahya
  for (let lvl = 0; lvl <= W; lvl++) {
    const half = W - lvl;
    const y = base.y + 3 + lvl;
    for (let x = -half; x <= half; x++) for (let z = -W; z <= W; z++) {
      if (Math.abs(x) === half) out.push([base.x + x, y, base.z + z, "minecraft:oak_planks"]);
    }
    if (half === 0) for (let z = -W; z <= W; z++) out.push([base.x, y, base.z + z, "minecraft:oak_planks"]);
  }
  // alın duvarları (çatı üçgeninin ön/arka kapaması)
  for (let lvl = 1; lvl <= W - 1; lvl++) {
    const half = W - lvl;
    const y = base.y + 2 + lvl;
    for (const z of [-W, W]) for (let x = -half + 1; x <= half - 1; x++) {
      out.push([base.x + x, y, base.z + z, "minecraft:oak_planks"]);
    }
  }
  // iç eşya (zemin+1)
  const F = [];
  F.push([base.x - 2, base.y + 1, base.z + 2, "minecraft:chest"]);
  F.push([base.x - 1, base.y + 1, base.z + 2, "minecraft:chest"]);
  F.push([base.x + 2, base.y + 1, base.z + 2, "minecraft:crafting_table"]);
  F.push([base.x + 2, base.y + 1, base.z + 1, "minecraft:furnace"]);
  F.push([base.x - 2, base.y + 1, base.z - 1, "minecraft:bed"]);
  if (countInv(st, "minecraft:enchanting_table") > 0) F.push([base.x, base.y + 1, base.z + 1, "minecraft:enchanting_table"]);
  return out.concat(F);
}

function placeSpecial(worker, pos, id) {
  if (id === "minecraft:bed") {
    try {
      worker.dimension.runCommand(`setblock ${pos.x} ${pos.y} ${pos.z} bed ["direction"=0]`);
      worker.dimension.runCommand(`setblock ${pos.x} ${pos.y} ${pos.z + 1} bed ["direction"=0,"head_piece_bit"=true]`);
      return true;
    } catch (e) { return setBlock(worker.dimension, pos, "minecraft:white_wool"); }
  }
  return setBlock(worker.dimension, pos, id);
}

function depositToChest(worker, st, chestPos) {
  try {
    const cont = blockAt(worker.dimension, chestPos)?.getComponent("minecraft:inventory")?.container;
    if (!cont) return 0;
    let moved = 0;
    for (const [id, n] of Object.entries({ ...st.inventory })) {
      if (n <= 8 || isToolItem(id) || KEEP_IN_HAND.has(id)) continue;
      let surplus = n - 8; // her kalemden 8 yedek NPC'de kalır
      removeInv(st, id, surplus);
      while (surplus > 0) {
        const put = Math.min(64, surplus);
        try { cont.addItem(new ItemStack(id, put)); } catch (e) { surplus = 0; break; }
        moved += put;
        surplus -= put;
      }
    }
    return moved;
  } catch (e) { return 0; }
}

/** SIM-S7 kök düzeltmesi: ihtiyaç = KALAN plan; toplam değil.
 *  Eski kod her tick toplam malzemeyi şart koşuyordu → duvar harcandıkça
 *  sonsuz 'taş topla' alt-görev döngüsü + NPC kendi evinin altına kuyu. */
function remainingNeeds(plan, index, st) {
  const need = {};
  for (let i = index; i < plan.length; i++) {
    const id = plan[i][3];
    need[id] = (need[id] ?? 0) + 1;
  }
  return need;
}

export function tickBuildHouse(worker, st, data) {
  if (!data.plan) {
    // plan kurulumu için başlangıç stoğu (bir kere)
    if (totalWood(st) < NEED_WOOD) return pushSubTask(st, "gather_wood", { tree: "any", amount: NEED_WOOD, reason: "ev" });
    if (countInv(st, "minecraft:cobblestone") < NEED_STONE) {
      return pushSubTask(st, "collect_block", { blockId: "minecraft:stone", amount: NEED_STONE, reason: "ev" });
    }
    data.plan = housePlan(st.base, st);
    data.index = 0;
    st.dirty = true;
  }
  const need = remainingNeeds(data.plan, data.index ?? 0, st);
  // kalan plank ihtiyacı: loglardan üret
  if ((need["minecraft:oak_planks"] ?? 0) > countInv(st, "minecraft:oak_planks")) {
    if (!craftPlanks(st, need["minecraft:oak_planks"])) {
      // SÖZLEŞME: gather_wood.amount = hedef TOPLAM log sayısı (delta değil!)
      const logsNow = totalWood(st) - countInv(st, "minecraft:oak_planks");
      return pushSubTask(st, "gather_wood", { tree: "any", amount: logsNow + 6, reason: "ev-plank" });
    }
  }
  // kalan taş ihtiyacı (yalnız plan hâlâ taş istiyorsa)
  if ((need["minecraft:cobblestone"] ?? 0) > countInv(st, "minecraft:cobblestone")) {
    // SIM ping-pong kök düzeltmesi: collect_block.amount = hedef TOPLAM.
    return pushSubTask(st, "collect_block", {
      blockId: "minecraft:stone",
      amount: need["minecraft:cobblestone"],
      reason: "ev-taş",
    });
  }
  // iç eşyalar: yalnız kalan planda geçenler craft edilir (yatak yün yoksa atlanır)
  for (const it of ["minecraft:chest", "minecraft:crafting_table", "minecraft:furnace", "minecraft:bed"]) {
    if ((need[it] ?? 0) > countInv(st, it)) craft(st, it);
  }
  while (data.index < data.plan.length) {
    const [x, y, z, id] = data.plan[data.index];
    const cur = blockIdAt(worker.dimension, { x, y, z });
    if (!isAir(cur)) { data.index++; continue; }
    const horizOk = horizDist(worker.location, { x: x + 0.5, z: z + 0.5 }) <= PLACE_RANGE;
    const dy = y - Math.floor(worker.location.y);
    if (!horizOk || Math.abs(dy) > 4) {
      // GERÇEK OYUNCU TEKNİĞİ (SIM-S7a): hedef yukarıda ve yatayda
      // yakınsa pillar-jump — zıpla, ayağının altına blok koy.
      if (horizOk && dy > 4) {
        const filler = ["minecraft:cobblestone", "minecraft:dirt", "minecraft:oak_planks"]
          .find((f) => countInv(st, f) > 0);
        if (filler) {
          const fx = Math.floor(worker.location.x), fy = Math.floor(worker.location.y), fz = Math.floor(worker.location.z);
          removeInv(st, filler, 1);
          worker.teleport({ x: fx + 0.5, y: fy + 1, z: fz + 0.5 }, { dimension: worker.dimension });
          setBlock(worker.dimension, { x: fx, y: fy, z: fz }, filler);
          playSoundAt(worker.dimension, "dig.stone", { x: fx, y: fy, z: fz });
          st.status = `Ev: iskele basamağı (pillar-jump) y=${fy + 1}`;
          st.dirty = true;
          return;
        }
      }
      st.status = `Ev: bloğa yürüyor ${data.index}/${data.plan.length}`;
      const r = walkTo(worker, { x, y, z }, { reach: 2 });
      if (r.blocked) { data.index++; st.dirty = true; }
      return;
    }
    // SIM-S7 kök düzeltmesi: NPC kendi ayak/kafa hücresine blok basıp
    // kendini GÖMÜYORDU. Aynı hücredeyse önce kenara çekil.
    const wf = { x: Math.floor(worker.location.x), y: Math.floor(worker.location.y), z: Math.floor(worker.location.z) };
    if ((x === wf.x && z === wf.z && (y === wf.y || y === wf.y + 1))) {
      st.status = "Ev: kendi hücresinden kenara çekiliyor";
      walkTo(worker, { x: x + 2, y: wf.y, z: z + 2 }, { reach: 0, arrive: 1.0 });
      return;
    }
    if (removeInv(st, id, 1) <= 0) { data.index++; continue; }
    faceBlock(worker, { x, y, z });
    placeSpecial(worker, { x, y, z }, id);
    playSoundAt(worker.dimension, id.includes("plank") || id === "minecraft:chest" ? "dig.wood" : "dig.stone", { x, y, z });
    try { worker.playAnimation("animation.autonpc.worker.swing"); } catch (e) { /* opsiyonel */ }
    st.skills.building++;
    st.status = `Ev yapıyor ${data.index + 1}/${data.plan.length}`;
    data.index++;
    st.dirty = true;
    return; // tick başına bir blok
  }
  // bitiş: fazla eşyayı sandığa koy
  const moved = depositToChest(worker, st, { x: st.base.x - 2, y: st.base.y + 1, z: st.base.z + 2 });
  st.flags = st.flags ?? {};
  st.flags.houseBuilt = true;
  st.dirty = true;
  finishTask(st, `Ev tamamlandı (çatı+iç eşya; sandığa ${moved} eşya kondu)`);
}
