## Port of upstream/pumpkin/src/block/blocks/soul_sand.rs.
## Same override as `mud.nim`: `is_pathfindable` always false.

import blockbehaviour
import blockmisc

proc registerSoulSand*() =
  let b = newBlockBehaviour()
  b.isPathfindableImpl = (proc(stateId: uint32, computationType: PathComputationType): bool {.closure.} =
    false)
  registerBlock("minecraft:soul_sand", b)
