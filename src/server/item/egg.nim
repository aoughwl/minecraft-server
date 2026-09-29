## Port of upstream/pumpkin/src/item/items/egg.rs's `EggItem`.
##
## Deliberately does NOT import itembehaviour.nim, same reasoning as
## dye.nim/swords.nim/mace.nim/snowball.nim: the ItemBehaviour vtable's
## closures hit the closures-through-vtables crash from mere reachability
## in the binary (NIMONY-COMPILER-BUGS.md #1), so this stays a free proc
## wired into an actual ItemBehaviour.normalUse field by whatever file
## builds EggItem's registration, not here.
##
## `EggItem::ids()` covers egg/blue_egg/brown_egg (dyed chicken variants);
## matched here by name prefix rather than three hardcoded ids, since the
## generated item table doesn't group them.

import ../entity/entity
import ../entity/egg as eggEntity
import ../world/worldstub
import ../../world/tick  # BlockPos, blockPos
import ../../util/legacy_rand
import ../../inventory/itemstub
import ../../util/gamemode

const Power = 1.5'f32

proc isEggStack(s: ItemStack): bool =
  let name = getName(s)
  name == "egg" or name == "blue_egg" or name == "brown_egg"

proc eggNormalUse*(player: Player, world: World, nextEntityId: int32,
                   entityUuid: string, rand: var LegacyRand) =
  ## Port of `EggItem::normal_use`. Same shape as `snowballNormalUse`, plus
  ## propagating the held stack onto the thrown entity so clients render
  ## the correct dyed-egg variant.
  let position = player.position()
  playSound(world, "entity.egg.throw", "players", blockPos(
    int32(position.x), int32(position.y), int32(position.z)))

  let itemStack = player.heldItem()
  let e = newEntity(nextEntityId, entityUuid, EntityDimensions(width: 0.25'f32, height: 0.25'f32, eyeHeight: 0.125'f32))
  let egg = newEggEntityShot(e, player.getEntity())
  setItemStack(egg, itemStack)

  var thrown = egg.thrown
  let (yaw, pitch) = player.rotation()
  setVelocityFrom(thrown, rand, pitch, yaw, 0.0'f32, Power, 1.0'f32)
  spawnEntity(world, "egg", entityUuid, blockPos(
    int32(e.pos.x), int32(e.pos.y), int32(e.pos.z)))

  var mainHand = player.heldItem()
  let consumed =
    if not isEmpty(mainHand) and isEggStack(mainHand):
      decrementUnlessCreative(mainHand, player.gamemode, 1)
      player.setHeldItem(mainHand)
      true
    else:
      false

  if not consumed:
    var offHand = player.offHandItem()
    if not isEmpty(offHand) and isEggStack(offHand):
      decrementUnlessCreative(offHand, player.gamemode, 1)
      player.setStackInHand(true, offHand)
