## Port of upstream/pumpkin/src/block/blocks/glazed_terracotta.rs
##
## Upstream registers this for the `minecraft:glazed_terracotta` tag (all
## 16 dye-colored variants) via `#[pumpkin_block_from_tag(...)]`; ported
## against one representative member (`white_glazed_terracotta`), same
## approach `logs.nim` takes for the `minecraft:logs` tag - no tag-
## membership data exists yet, so the rest of the tag's members register
## the same way once it does.
##
## `get_horizontal_facing()` isn't a method on this port's `Entity` (only
## raw `yaw`/`pitch` fields exist, see src/server/entity/entity.nim) so
## the standard Minecraft yaw-quantization formula is reproduced locally
## here rather than added to entity.nim, which is out of scope for this
## block-only pass.

import std/math
import blockbehaviour
import blockstateid
import blockmisc
import ../entity/entity

proc horizontalFacingFromYaw(yaw: float32): BlockDirection =
  ## `Direction.fromYRot`: index = floor(yaw/90 + 0.5) mod 4,
  ## mapped south/west/north/east in that order.
  var idx = int(floor(yaw / 90.0'f32 + 0.5'f32)) mod 4
  if idx < 0: idx += 4
  case idx
  of 0: bdSouth
  of 1: bdWest
  of 2: bdNorth
  else: bdEast

proc opposite(d: BlockDirection): BlockDirection =
  case d
  of bdNorth: bdSouth
  of bdSouth: bdNorth
  of bdEast: bdWest
  of bdWest: bdEast
  of bdUp: bdDown
  of bdDown: bdUp

const BlockName = "white_glazed_terracotta"

proc onPlaceGlazedTerracotta*(player: nil Player): int =
  let facing = if player == nil: bdNorth
               else: opposite(horizontalFacingFromYaw(player.livingEntity.entity.yaw))
  let facingName = case facing
    of bdNorth: "north"
    of bdSouth: "south"
    of bdEast: "east"
    of bdWest: "west"
    of bdUp: "up"
    of bdDown: "down"
  let props = @[("facing", facingName)]
  let r = resolveStateId(BlockName, props)
  if r.ok: r.stateId else: defaultOnPlace(BlockName)

proc newGlazedTerracottaBlock*(): BlockBehaviour =
  var b = newBlockBehaviour(BlockName)
  # `onPlaceImpl`'s fixed (direction, waterlogged) signature doesn't carry
  # a player reference (see blockbehaviour.nim - scoped to what chain.rs
  # needed), so this block's real "use the placing player's facing" logic
  # lives in `onPlaceGlazedTerracotta` for a caller with player access to
  # call directly; the vtable entry falls back to `defaultOnPlace` (no
  # player available through this narrower interface).
  b.onPlaceImpl = (proc(direction: BlockDirection, waterlogged: bool): int {.closure.} =
    discard direction
    discard waterlogged
    defaultOnPlace(BlockName))
  b

proc registerGlazedTerracottaBlock*() =
  registerBlock(BlockName, newGlazedTerracottaBlock())
