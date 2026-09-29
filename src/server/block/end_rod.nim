## Port of upstream/pumpkin/src/block/blocks/end_rod.rs.
##
## Proof case for `src/server/world/worldstub.nim`'s `getNeighborBlockState`
## (just added) - `on_place` here reads the block state in the direction
## the rod is being placed FROM (i.e. the block on the other side of the
## placement direction) and picks a facing based on whether that neighbor
## is *also* an end rod pointing back at this one.
##
## Not wired through `BlockBehaviour.onPlaceImpl`: that closure's fixed
## signature (`direction, waterlogged: bool): int`) has no room for a
## `World`/position, and no real block-placement call site exists yet in
## this port to supply one meaningfully - `chain.nim`'s state-only variant
## fits that signature because it never needs to look outside the placed
## block itself. `onPlaceEndRod` is exposed directly instead, matching this
## file's real logic 1:1 and testable on its own; wire it into the vtable
## via a new `onPlaceWithWorldImpl` field once a real placement call site
## exists.

import blockbehaviour
import blockstateid
import blockmisc  # PathComputationType
import ../world/worldstub
import ../../world/tick  # BlockPos

const BlockName = "minecraft:end_rod"

proc opposite(dir: BlockDirection): BlockDirection =
  case dir
  of bdNorth: bdSouth
  of bdSouth: bdNorth
  of bdEast: bdWest
  of bdWest: bdEast
  of bdUp: bdDown
  of bdDown: bdUp

proc facingName(dir: BlockDirection): string =
  case dir
  of bdNorth: "north"
  of bdSouth: "south"
  of bdEast: "east"
  of bdWest: "west"
  of bdUp: "up"
  of bdDown: "down"

proc onPlaceEndRod*(w: World, pos: BlockPos, direction: BlockDirection): int =
  ## Port of `EndRodBlock::on_place`. `args.direction` is the face the
  ## player was looking at when placing (upstream reuses it directly as
  ## the rod's default facing, or flips it if the neighbor in that
  ## direction is another end rod already facing back).
  let (dx, dy, dz) = directionOffset(direction)
  let neighborState = int(getNeighborBlockState(w, pos, dx, dy, dz))

  let oppositeFacing = facingName(opposite(direction))
  var matches = false
  if isStateOfBlock("end_rod", neighborState):
    let pr = statePropValues("end_rod", neighborState)
    if pr.ok:
      for i in 0 ..< pr.values.len:
        if pr.values[i][0] == "facing" and pr.values[i][1] == oppositeFacing:
          matches = true

  let chosenFacing = if matches: facingName(direction) else: oppositeFacing
  let r = resolveStateId("end_rod", @[("facing", chosenFacing)])
  if r.ok: r.stateId else: defaultOnPlace("end_rod")

proc newEndRodBlock*(): BlockBehaviour =
  var b = newBlockBehaviour("end_rod")
  b.isPathfindableImpl = (proc(stateId: uint32, computationType: PathComputationType): bool {.closure.} =
    discard stateId
    discard computationType
    false)
  b

proc registerEndRodBlock*() =
  registerBlock(BlockName, newEndRodBlock())
