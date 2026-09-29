## Port of upstream/pumpkin/src/block/blocks/logs.rs
##
## Upstream registers this behaviour for the whole `minecraft:logs` tag
## (every log/wood/stem block) via `#[pumpkin_block_from_tag(...)]` - no
## tag-membership data is ported yet (see src/data_codegen/README.md), so
## this proves the pattern against one representative member, `oak_log`,
## the same block `blockstateidtest.nim` already uses as its single-
## property proof case. Registering it for the rest of the tag's members
## is mechanical once real tag data exists - swap the one `registerBlock`
## call for a loop over the tag's block names.

import blockbehaviour
import blockstateid
import blockmisc

const BlockName = "oak_log"

proc axisOf(direction: BlockDirection): string =
  case direction
  of bdEast, bdWest: "x"
  of bdUp, bdDown: "y"
  of bdNorth, bdSouth: "z"

proc onPlaceLog(direction: BlockDirection): int =
  let props = @[("axis", axisOf(direction))]
  let r = resolveStateId(BlockName, props)
  if r.ok: r.stateId else: defaultOnPlace(BlockName)

proc newLogBlock*(): BlockBehaviour =
  var b = newBlockBehaviour(BlockName)
  b.onPlaceImpl = (proc(direction: BlockDirection, waterlogged: bool): int {.closure.} =
    discard waterlogged
    onPlaceLog(direction))
  b

proc registerLogBlock*() =
  registerBlock(BlockName, newLogBlock())
