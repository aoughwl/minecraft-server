## Port of upstream/pumpkin/src/block/blocks/mud.rs.
## Overrides `is_pathfindable` to always return false, unconditionally on
## `computation_type` - mud blocks are impassable for pathfinding purposes.

import blockbehaviour
import blockmisc

proc registerMud*() =
  let b = newBlockBehaviour()
  b.isPathfindableImpl = (proc(stateId: uint32, computationType: PathComputationType): bool {.closure.} =
    false)
  registerBlock("minecraft:mud", b)
