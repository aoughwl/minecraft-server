## Port of upstream/pumpkin/src/item/items/snowball.rs's `SnowBallItem`.
##
## Deliberately does NOT import itembehaviour.nim, same reasoning as
## dye.nim/swords.nim/mace.nim: the ItemBehaviour vtable's closures hit the
## closures-through-vtables crash from mere reachability in the binary
## (NIMONY-COMPILER-BUGS.md #1), so this stays a free proc wired into an
## actual ItemBehaviour.normalUse field by whatever file builds
## SnowBallItem's registration, not here.
##
## Item id (`Item.SNOWBALL`), and any `apply_to_projectile_spawned`
## enchantment hooks, are out of scope for the same reasons noted in
## projectile.nim's own doc comment (no `EnchantmentHelper` ported yet).

import ../entity/entity
import ../entity/snowball as snowballEntity
import ../world/worldstub
import ../../world/tick  # BlockPos, blockPos
import ../../util/legacy_rand
import ../../inventory/itemstub
import ../../util/gamemode

const Power = 1.5'f32

proc isSnowballStack(s: ItemStack): bool =
  getName(s) == "snowball"

proc snowballNormalUse*(player: Player, world: World, nextEntityId: int32,
                        entityUuid: string, rand: var LegacyRand) =
  ## Port of `SnowBallItem::normal_use`. Spawns a thrown snowball entity
  ## from the player's position/rotation, records the throw sound and the
  ## spawned entity via the World stub, then consumes one snowball from
  ## whichever hand holds it (main hand first, falling back to off hand),
  ## matching upstream's exact fallback order.
  let position = player.position()
  playSound(world, "entity.snowball.throw", "neutral", blockPos(
    int32(position.x), int32(position.y), int32(position.z)))

  let e = newEntity(nextEntityId, entityUuid, EntityDimensions(width: 0.25'f32, height: 0.25'f32, eyeHeight: 0.125'f32))
  let snow = newSnowballEntityShot(e, player.getEntity())
  var thrown = snow.thrown
  let (yaw, pitch) = player.rotation()
  setVelocityFrom(thrown, rand, pitch, yaw, 0.0'f32, Power, 1.0'f32)
  spawnEntity(world, "snowball", entityUuid, blockPos(
    int32(e.pos.x), int32(e.pos.y), int32(e.pos.z)))

  var mainHand = player.heldItem()
  let consumed =
    if not isEmpty(mainHand) and isSnowballStack(mainHand):
      decrementUnlessCreative(mainHand, player.gamemode, 1)
      player.setHeldItem(mainHand)
      true
    else:
      false

  if not consumed:
    var offHand = player.offHandItem()
    if not isEmpty(offHand) and isSnowballStack(offHand):
      decrementUnlessCreative(offHand, player.gamemode, 1)
      player.setStackInHand(true, offHand)
