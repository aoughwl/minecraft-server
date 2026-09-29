## Port of upstream/pumpkin/src/block/blocks/barrier.rs
##
## `on_place` only needs `args.replacing.water_source()` - a bool, not a
## World query - so it fits `onPlaceImpl`'s existing `(direction,
## waterlogged)` signature with `direction` simply unused. A single-property
## (waterlogged-only) sibling of chain.nim's two-property proof case.
##
## `get_state_for_neighbor_update`'s `schedule_fluid_tick` call needs a real
## World and is not ported - only `on_place`, following the same
## "port what's tractable, defer what needs World" line every other file
## in this directory draws.

import blockbehaviour
import blockstateid
import blockmisc

const BlockName = "minecraft:barrier"

proc onPlaceBarrier(waterlogged: bool): int =
  let props = @[("waterlogged", (if waterlogged: "true" else: "false"))]
  let r = resolveStateId("barrier", props)
  if r.ok: r.stateId else: defaultOnPlace("barrier")

proc newBarrierBlock*(): BlockBehaviour =
  var b = newBlockBehaviour("barrier")
  b.onPlaceImpl = (proc(direction: BlockDirection, waterlogged: bool): int {.closure.} =
    discard direction
    onPlaceBarrier(waterlogged))
  b

proc registerBarrierBlock*() =
  registerBlock(BlockName, newBarrierBlock())
