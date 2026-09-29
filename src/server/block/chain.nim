## Port of upstream/pumpkin/src/block/blocks/chain.rs
##
## The first block whose `on_place` actually resolves a real
## property-permuted state id (axis + waterlogged), rather than just
## returning the block's fixed default state - proof that
## `blockstateid.nim`'s resolution API unblocks the class of blocks the
## README flagged as needing it (`chain.rs`/`logs.rs`/`end_rod.rs`/
## `end_portal_frame.rs`/`glazed_terracotta.rs`).

import blockbehaviour
import blockstateid
import blockmisc

const BlockName = "minecraft:iron_chain"

proc onPlaceIronChain(direction: BlockDirection, waterlogged: bool): int =
  let axis = case direction
    of bdEast, bdWest: "x"
    of bdUp, bdDown: "y"
    of bdNorth, bdSouth: "z"
  let props = @[("axis", axis), ("waterlogged", (if waterlogged: "true" else: "false"))]
  let r = resolveStateId("iron_chain", props)
  if r.ok: r.stateId else: defaultOnPlace("iron_chain")

proc newChainBlock*(): BlockBehaviour =
  var b = newBlockBehaviour("iron_chain")
  b.onPlaceImpl = (proc(direction: BlockDirection, waterlogged: bool): int {.closure.} =
    onPlaceIronChain(direction, waterlogged))
  b.isPathfindableImpl = (proc(stateId: uint32, computationType: PathComputationType): bool {.closure.} =
    discard stateId
    discard computationType
    false)
  b

proc registerChainBlock*() =
  registerBlock(BlockName, newChainBlock())
