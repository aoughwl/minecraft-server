## Port of upstream/pumpkin/src/block/blocks/spreading_snowy_block.rs's
## `SnowyBlock` helper (podzol/mycelium's `snowy` state-property logic) and
## the `PodzolBlock`/`MyceliumBlock` concrete types that use it.
##
## Scope: only `SnowyBlock.is_snowy_setting`/`on_place`/
## `get_state_for_neighbor_update` are ported - the real logic
## `resolveStateId`/`getNeighborBlockState` (added for `end_rod.nim`) now
## make tractable. `SpreadingSnowyBlock`'s `random_tick`/`can_propagate`/
## `can_stay_alive` (upstream, same file) are NOT ported: they need a real
## block-tag system (`tag::Block::MINECRAFT_SNOW` membership - approximated
## below by exact-name match against `minecraft:snow`, not a real tag
## lookup, since no tag system exists yet), `LightEngine`'s light-dampening
## math, `World.is_loaded`/`get_max_local_raw_brightness`, and a random
## tick scheduler - none of which exist in this port. Documented as a real
## gap, not faked.
##
## Like `end_rod.nim`, exposed as direct procs taking `World`/`BlockPos`
## rather than forced through `BlockBehaviour.onPlaceImpl`'s fixed
## `(direction, waterlogged): int` signature, since no real placement call
## site exists yet to supply a `World`.

import blockbehaviour
import blockstateid
import ../world/worldstub
import ../../world/tick  # BlockPos

const
  PodzolName = "minecraft:podzol"
  MyceliumName = "minecraft:mycelium"

proc isSnowyBlockState(state: uint32): bool =
  ## Approximates upstream's `above_state.id.to_block().has_tag(&tag::Block::
  ## MINECRAFT_SNOW)` - the real tag membership check (snow block AND snow
  ## layers both carry that tag upstream). No tag system exists here yet, so
  ## this checks exact-name membership in the two blocks the tag is known to
  ## cover, rather than a real registry-backed tag lookup. TODO: replace with
  ## a real tag query once one exists.
  isStateOfBlock("minecraft:snow", int(state)) or
    isStateOfBlock("minecraft:snow_block", int(state))

proc snowyOnPlace*(blockName: string, w: World, pos: BlockPos): int =
  ## Port of `SnowyBlock::on_place`: resolves the placed block's `snowy`
  ## property from whether the block directly above is snow.
  let above = blockPos(pos.x, pos.y + 1, pos.z)
  let aboveState = getBlockState(w, above)
  let snowy = isSnowyBlockState(aboveState)
  let r = resolveStateId(blockName, @[("snowy", $snowy)])
  if r.ok: r.stateId else: defaultOnPlace(blockName)

proc snowyGetStateForNeighborUpdate*(blockName: string, stateId: int,
    directionIsUp: bool, neighborState: uint32): int =
  ## Port of `SnowyBlock::get_state_for_neighbor_update`. Upstream only acts
  ## when the updated neighbor is the block directly above; every other
  ## direction returns the state unchanged.
  if not directionIsUp:
    return stateId
  let shouldBeSnowy = isSnowyBlockState(neighborState)
  let pr = statePropValues(blockName, stateId)
  if not pr.ok:
    return stateId
  var currentSnowy = false
  for i in 0 ..< pr.values.len:
    if pr.values[i][0] == "snowy":
      currentSnowy = pr.values[i][1] == "true"
  if currentSnowy == shouldBeSnowy:
    return stateId
  let r = resolveStateId(blockName, @[("snowy", $shouldBeSnowy)])
  if r.ok: r.stateId else: stateId

proc podzolOnPlace*(w: World, pos: BlockPos): int =
  snowyOnPlace(PodzolName, w, pos)

proc myceliumOnPlace*(w: World, pos: BlockPos): int =
  snowyOnPlace(MyceliumName, w, pos)

proc newPodzolBlock*(): BlockBehaviour =
  newBlockBehaviour(PodzolName)

proc newMyceliumBlock*(): BlockBehaviour =
  newBlockBehaviour(MyceliumName)

proc registerPodzolBlock*() =
  registerBlock(PodzolName, newPodzolBlock())

proc registerMyceliumBlock*() =
  registerBlock(MyceliumName, newMyceliumBlock())
