import { __mock, __makePlayer, __errors, world } from "@minecraft/server";
const dropFor = (await import("../BP/scripts/core/registry.js")).dropFor;
__mock.dropResolver = dropFor;
const ow = world.getDimension("overworld");
const player = __makePlayer("M", { x: 0.5, y: 64, z: 0.5 }, ow);
await import("../BP/scripts/main.js");
const workers = await import("../BP/scripts/sys/workers.js");
const persist = await import("../BP/scripts/core/persist.js");
const stateMod = await import("../BP/scripts/core/state.js");
const w = workers.spawnWorker(player);
const st = persist.loadState(w);
stateMod.addInv(st, "minecraft:oak_log", 50);
stateMod.addInv(st, "minecraft:cobblestone", 40);
st.base = { x: 20, y: 64, z: 20 };
stateMod.setTask(st, "build_house", {});
let lastStatus = "";
for (let t = 0; t < 6000; t += 50) {
  __mock.tick(50);
  const sig = `${st.status} | idx=${st.task?.data?.index} | pos=${Math.floor(w.location.x)},${Math.floor(w.location.y)},${Math.floor(w.location.z)} | task=${st.task?.type}`;
  if (sig !== lastStatus) { console.log(t, sig); lastStatus = sig; }
  if (!st.task) break;
}
console.log("errors:", __errors.length, __errors[0]?.split("\n")[0] ?? "");
