import { __mock, __makePlayer, __errors, world } from "@minecraft/server";
const reg = await import("../BP/scripts/core/registry.js");
__mock.dropResolver = reg.dropFor;
const ow = world.getDimension("overworld");
const player = __makePlayer("M", { x: 0.5, y: 64, z: 0.5 }, ow);
await import("../BP/scripts/main.js");
const workers = await import("../BP/scripts/sys/workers.js");
const persist = await import("../BP/scripts/core/persist.js");
const stateMod = await import("../BP/scripts/core/state.js");
const bh = await import("../BP/scripts/jobs/build_house.js");
const w = workers.spawnWorker(player);
const st = persist.loadState(w);
stateMod.addInv(st, "minecraft:oak_log", 50);
stateMod.addInv(st, "minecraft:cobblestone", 40);
st.base = { x: 20, y: 64, z: 20 };
stateMod.setTask(st, "build_house", {});
// job'u DOĞRUDAN çağır
const data = st.task.data;
try {
  bh.tickBuildHouse(w, st, data);
  console.log("1.çağrı:", st.status, "| task:", st.task?.type, "| plan:", data.plan?.length, "| planks:", stateMod.countInv(st,"minecraft:oak_planks"), "| cobble:", stateMod.countInv(st,"minecraft:cobblestone"));
} catch (e) { console.log("JOB THROW:", e.stack?.split("\n").slice(0,3).join(" | ")); }
for (let i=0;i<5;i++) {
  try { const t=st.task; if(!t) break; const jobs=(await import("../BP/scripts/jobs/index.js")).JOBS; jobs[t.type](w, st, t.data ?? (t.data={})); console.log(`çağrı${i+2}:`, st.status, "| task:", st.task?.type); }
  catch (e) { console.log("THROW:", e.stack?.split("\n").slice(0,2).join(" | ")); break; }
}
