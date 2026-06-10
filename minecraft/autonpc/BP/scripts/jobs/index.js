/** AutoNPC v4.0 — görev tipi → işleyici kaydı. */
import { tickGatherWood, tickCollectLeaves } from "./gather_wood.js";
import { tickCollectBlock } from "./collect_block.js";
import { tickMineOre } from "./mine_ore.js";
import { tickBuildHouse } from "./build_house.js";
import { tickWalkTest } from "./walk_test.js";

export const JOBS = {
  gather_wood: tickGatherWood,
  collect_leaves: tickCollectLeaves,
  collect_block: tickCollectBlock,
  mine_ore: tickMineOre,
  build_house: tickBuildHouse,
  walk_test: tickWalkTest,
};
