## Port of upstream/pumpkin/src/block/blocks/mangrove_roots.rs
##
## Same shape as barrier.nim: `on_place` only needs a `waterlogged` bool,
## fits the existing `onPlaceImpl` signature with `direction` unused.
## `get_state_for_neighbor_update`'s `schedule_fluid_tick` needs a real
## World and is not ported.

import blockbehaviour
import blockstateid
import blockmisc

const BlockName = "minecraft:mangrove_roots"

proc onPlaceMangroveRoots(waterlogged: bool): int =
  let props = @[("waterlogged", (if waterlogged: "true" else: "false"))]
  let r = resolveStateId("mangrove_roots", props)
  if r.ok: r.stateId else: defaultOnPlace("mangrove_roots")

proc newMangroveRootsBlock*(): BlockBehaviour =
  var b = newBlockBehaviour("mangrove_roots")
  b.onPlaceImpl = (proc(direction: BlockDirection, waterlogged: bool): int {.closure.} =
    discard direction
    onPlaceMangroveRoots(waterlogged))
  b

proc registerMangroveRootsBlock*() =
  registerBlock(BlockName, newMangroveRootsBlock())
