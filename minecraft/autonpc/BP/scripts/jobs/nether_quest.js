/**
 * AutoNPC v5.0 — Nether görevi (aşama makinesi).
 * 0 hazırlık: elmas kazma + 10 obsidyen + yataklar + çakmak
 * 1 portal: çerçeveyi GERÇEK obsidyenle ör (yürüyerek), içini portal bloğuyla yak
 * 2 geçiş: portala yürü → nether'e geç (boyut teleport; PLAN_V5 dürüst sınır)
 * 3 debris: ancient_debris tara; yoksa YATAĞI 9 BLOK İLERİYE koy, geri çekil,
 *   GERÇEK patlama (createExplosion) — vanilla yatak-madenciliği taktiği
 * 4 üretim: scrap→ingot→netherite alet/zırh upgrade, eve dön
 */
import { world } from "@minecraft/server";
import { finishTask, countInv, removeInv, pushSubTask, blacklistPos } from "../core/state.js";
import { craft, craftUpTo } from "../core/recipes.js";
import { blockIdAt, setBlock, playSoundAt } from "../sys/blocks.js";
import { scanStep } from "../work/scanner.js";
import { approachAndBreak, canInteract } from "./job.js";
import { walkTo, clearNav } from "../nav/locomotion.js";
import { equipBestArmor } from "../combat/gear.js";
import { standable } from "../nav/grid.js";
import { isAir } from "../core/registry.js";
import { dist } from "../core/math.js";

const NEED_OBSIDIAN = 10;
const NEED_BEDS = 4;
const DEBRIS_TARGET = 4;

function portalFrame(base) {
  // dikey çerçeve: 4 taban+4 tavan değil — standart 4x5 köşesiz: yanlar 3'er, alt/üst 2'şer
  const o = [];
  const { x, y, z } = base;
  for (const dy of [1, 2, 3]) { o.push({ x, y: y + dy, z }); o.push({ x: x + 3, y: y + dy, z }); }
  for (const dx of [1, 2]) { o.push({ x: x + dx, y, z }); o.push({ x: x + dx, y: y + 4, z }); }
  return o;
}
function portalInner(base) {
  const o = [];
  for (const dx of [1, 2]) for (const dy of [1, 2, 3]) o.push({ x: base.x + dx, y: base.y + dy, z: base.z });
  return o;
}

function safeNetherSpot(dim, cx, cz) {
  for (let y = 40; y <= 100; y++) {
    if (standable(dim, cx, y, cz)) return { x: cx + 0.5, y, z: cz + 0.5 };
  }
  return undefined;
}

export function tickNetherQuest(worker, st, data) {
  data.stage = data.stage ?? 0;

  // ---- 0: hazırlık ----
  if (data.stage === 0) {
    if (countInv(st, "minecraft:diamond_pickaxe") + countInv(st, "minecraft:netherite_pickaxe") < 1) {
      if (countInv(st, "minecraft:diamond") >= 3) {
        // elmas kazma tarifi tools.js zincirinde yok; doğrudan üret
        removeInv(st, "minecraft:diamond", 3);
        if (countInv(st, "minecraft:stick") < 2) craft(st, "minecraft:stick");
        removeInv(st, "minecraft:stick", 2);
        st.inventory["minecraft:diamond_pickaxe"] = 1;
        st.dirty = true;
      } else return pushSubTask(st, "mine_ore", { group: "diamond", amount: 3, reason: "nether" });
    }
    if (countInv(st, "minecraft:obsidian") < NEED_OBSIDIAN) {
      return pushSubTask(st, "collect_block", { blockId: "minecraft:obsidian", amount: NEED_OBSIDIAN, reason: "portal" });
    }
    if (countInv(st, "minecraft:bed") < NEED_BEDS) {
      const r = craftUpTo(st, "minecraft:bed", NEED_BEDS);
      if (!r.ok) {
        if (r.missing.item === "minecraft:wool") return pushSubTask(st, "hunt", { animal: "sheep", amount: 4, reason: "yatak" });
        return pushSubTask(st, "gather_wood", { tree: "any", amount: 6, reason: "yatak" });
      }
    }
    if (countInv(st, "minecraft:flint_and_steel") < 1) {
      const r = craft(st, "minecraft:flint_and_steel");
      if (!r.ok) {
        if (r.missing.item === "minecraft:flint") return pushSubTask(st, "collect_block", { blockId: "minecraft:gravel", amount: 4, reason: "çakmaktaşı" });
        return pushSubTask(st, "mine_ore", { group: "iron", amount: 2, reason: "çakmak" });
      }
    }
    // çakıldan flint sim: 4 çakıl → 1 flint
    if (countInv(st, "minecraft:flint") < 1 && countInv(st, "minecraft:gravel") >= 4) {
      removeInv(st, "minecraft:gravel", 4);
      st.inventory["minecraft:flint"] = (st.inventory["minecraft:flint"] ?? 0) + 1;
      st.dirty = true;
      return;
    }
    equipBestArmor(worker, st);
    data.stage = 1;
    data.portalBase = { x: st.base.x + 4, y: st.base.y, z: st.base.z + 4 };
    data.frameIdx = 0;
    st.dirty = true;
    return;
  }

  // ---- 1: portal inşası ----
  if (data.stage === 1) {
    const frame = portalFrame(data.portalBase);
    while (data.frameIdx < frame.length && blockIdAt(worker.dimension, frame[data.frameIdx]) === "minecraft:obsidian") data.frameIdx++;
    if (data.frameIdx < frame.length) {
      const pos = frame[data.frameIdx];
      if (!canInteract(worker, pos, 4.0, 5)) {
        st.status = `Portal çerçevesi: bloğa yürüyor ${data.frameIdx + 1}/${frame.length}`;
        const r = walkTo(worker, pos, { reach: 2 });
        if (r.blocked) return finishTask(st, "Portal yerine ulaşılamadı");
        return;
      }
      if (removeInv(st, "minecraft:obsidian", 1) <= 0) return finishTask(st, "Obsidyen bitti");
      setBlock(worker.dimension, pos, "minecraft:obsidian");
      playSoundAt(worker.dimension, "dig.stone", pos);
      try { worker.playAnimation("animation.autonpc.worker.swing"); } catch (e) { /* opsiyonel */ }
      data.frameIdx++;
      st.dirty = true;
      return;
    }
    // yak: iç hücrelere portal bloğu
    st.status = "Portali yakıyor";
    for (const pos of portalInner(data.portalBase)) {
      try { worker.dimension.runCommand(`setblock ${pos.x} ${pos.y} ${pos.z} portal`); }
      catch (e) { setBlock(worker.dimension, pos, "minecraft:fire"); }
    }
    playSoundAt(worker.dimension, "fire.ignite", data.portalBase, 0.8);
    data.stage = 2;
    st.dirty = true;
    return;
  }

  // ---- 2: nether'e geçiş ----
  if (data.stage === 2) {
    const inner = portalInner(data.portalBase)[1];
    if (dist(worker.location, { x: inner.x + 0.5, y: inner.y, z: inner.z + 0.5 }) > 1.2) {
      st.status = "Portala yürüyor";
      walkTo(worker, inner, { reach: 0, arrive: 1.1 });
      return;
    }
    const nether = world.getDimension("nether");
    const cx = Math.floor(st.base.x / 8), cz = Math.floor(st.base.z / 8);
    const spot = safeNetherSpot(nether, cx, cz) ?? { x: cx + 0.5, y: 70, z: cz + 0.5 };
    try {
      clearNav(worker.id);
      worker.teleport(spot, { dimension: nether });
      st.status = "Nether'de!";
      data.stage = 3;
      data.blast = undefined;
      st.dirty = true;
    } catch (e) { st.status = "Nether geçişi başarısız"; }
    return;
  }

  // ---- 3: ancient debris ----
  if (data.stage === 3) {
    if (countInv(st, "minecraft:ancient_debris") >= DEBRIS_TARGET) { data.stage = 4; st.dirty = true; return; }

    // patlama bekleniyorsa: geri çekil → patlat
    if (data.blast) {
      const b = data.blast;
      if (dist(worker.location, b) < 7) {
        st.status = "Patlama mesafesine çekiliyor";
        walkTo(worker, { x: Math.floor(b.x - 8), y: Math.floor(worker.location.y), z: Math.floor(b.z) }, { reach: 1 });
        return;
      }
      try {
        setBlock(worker.dimension, b, "minecraft:air"); // yatağı kaldır (patlama bizden)
        worker.dimension.createExplosion({ x: b.x + 0.5, y: b.y + 0.5, z: b.z + 0.5 }, 5, { breaksBlocks: true, causesFire: false });
        st.status = "BOOM! Debris taranıyor";
      } catch (e) { st.status = "Patlama başarısız"; }
      data.blast = undefined;
      st.dirty = true;
      return;
    }

    const r = scanStep(worker, "debris", 14, (id) => id === "minecraft:ancient_debris");
    if (r.scanning) { st.status = "Ancient debris aranıyor"; return; }
    if (r.found) {
      const br = approachAndBreak(worker, st, r.found, { drop: "minecraft:ancient_debris", skill: "mining" }, "Debris");
      if (br.failed) blacklistPos(st, r.found);
      return;
    }
    // debris görünmüyor: yatak-patlatma (yatağı 9 blok İLERİYE koy — vanilla taktiği)
    if (countInv(st, "minecraft:bed") < 1) return finishTask(st, `Yatak bitti; debris ${countInv(st, "minecraft:ancient_debris")}/${DEBRIS_TARGET}`);
    const dir = data.blastDir ?? (data.blastDir = { x: 1, z: 0 });
    const spot = {
      x: Math.floor(worker.location.x) + dir.x * 9,
      y: Math.max(12, Math.floor(worker.location.y)),
      z: Math.floor(worker.location.z) + dir.z * 9,
    };
    if (!canInteract(worker, spot, 9.5, 6)) {
      st.status = "Yatak noktasına ilerliyor";
      const w = walkTo(worker, { x: spot.x - dir.x * 2, y: spot.y, z: spot.z - dir.z * 2 }, { reach: 1 });
      if (w.blocked) {
        // önü kapalıysa tünelle (approachAndBreak spot'a doğru kırar)
        approachAndBreak(worker, st, spot, { drop: "minecraft:air", skill: "mining" }, "Nether tüneli");
      }
      return;
    }
    removeInv(st, "minecraft:bed", 1);
    setBlock(worker.dimension, spot, "minecraft:air");
    try { worker.dimension.runCommand(`setblock ${spot.x} ${spot.y} ${spot.z} bed`); }
    catch (e) { /* yatak görseli opsiyonel; patlama yine olacak */ }
    // yön döndür: sonraki patlama farklı hatta
    data.blastDir = { x: -dir.z, z: dir.x };
    data.blast = spot;
    st.status = "Yatak yerleştirildi; geri çekiliyor";
    st.dirty = true;
    return;
  }

  // ---- 4: netherite üretimi + eve dönüş ----
  if (data.stage === 4) {
    craftUpTo(st, "minecraft:netherite_scrap", Math.min(4, countInv(st, "minecraft:ancient_debris")));
    if (countInv(st, "minecraft:netherite_ingot") < 1) {
      const r = craft(st, "minecraft:netherite_ingot");
      if (!r.ok && r.missing.item === "minecraft:gold_ingot") {
        return pushSubTask(st, "mine_ore", { group: "gold", amount: 4, reason: "netherite" });
      }
    }
    for (const up of ["minecraft:netherite_sword", "minecraft:netherite_pickaxe", "minecraft:netherite_chestplate", "minecraft:netherite_helmet", "minecraft:netherite_leggings", "minecraft:netherite_boots"]) {
      if (countInv(st, "minecraft:netherite_ingot") < 1) break;
      craft(st, up);
    }
    equipBestArmor(worker, st);
    // eve dön
    try {
      clearNav(worker.id);
      worker.teleport({ x: st.base.x + 0.5, y: st.base.y + 1, z: st.base.z + 0.5 }, { dimension: world.getDimension("overworld") });
    } catch (e) { /* zaten overworld olabilir */ }
    return finishTask(st, `Nether görevi bitti: netherite ${countInv(st, "minecraft:netherite_ingot")} ingot + ekipman`);
  }
}
