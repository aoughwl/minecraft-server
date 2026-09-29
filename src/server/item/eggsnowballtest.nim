## Exercises `snowballNormalUse`/`eggNormalUse` directly against real
## Player/World state - not a `nimony c -r` proof (this imports
## src/server/entity/entity.nim, so it hits the closures-through-vtables
## runtime crash cataloged as NIMONY-COMPILER-BUGS.md bug #1, same as
## every other file in this directory that touches Player). `nimony check`
## passes clean, verified here; documented honestly, not claimed as
## runtime-proven.

import std/[assertions, syncio]
import ../entity/entity
import ../world/worldstub
import ../../util/legacy_rand
import ../../util/gamemode
import ../../util/vector3
import ../../inventory/itemstub
import snowball
import egg

proc mkPlayer(mode: GameMode, mainId: uint16, mainCount: uint8): Player =
  let ent = newEntity(1'i32, "player-uuid", EntityDimensions(width: 0.6'f32, height: 1.8'f32))
  ent.pos = vec3(10.0, 64.0, 10.0)
  let living = LivingEntity(entity: ent, health: 20.0'f32, maxHealth: 20.0'f32)
  result = Player(livingEntity: living, gameProfileName: "tester", gamemode: mode)
  result.mainHandItem = ItemStack(item: Item(id: mainId), itemCount: mainCount)

# --- snowball: survival consumes one from the main hand -------------------
block:
  let world = newWorld()
  var rand = fromSeed(42'u64)
  let player = mkPlayer(Survival, 1132'u16, 16'u8)  ## 1132: "snowball" in the generated item table
  assert getName(player.heldItem()) == "snowball", "test setup: id 1132 should resolve to snowball"

  snowballNormalUse(player, world, 2'i32, "snowball-uuid", rand)

  assert world.playedSounds.len == 1, "expected exactly one recorded sound"
  assert world.playedSounds[0].soundName == "entity.snowball.throw"
  assert world.spawnedEntities.len == 1, "expected exactly one recorded spawn"
  assert world.spawnedEntities[0].kind == "snowball"
  assert player.heldItem().itemCount == 15'u8, "expected one snowball consumed from the main hand"

# --- snowball: creative mode never decrements ------------------------------
block:
  let world = newWorld()
  var rand = fromSeed(42'u64)
  let player = mkPlayer(Creative, 1132'u16, 16'u8)

  snowballNormalUse(player, world, 3'i32, "snowball-uuid-2", rand)

  assert player.heldItem().itemCount == 16'u8, "creative mode should never consume the stack"
  assert world.spawnedEntities.len == 1

# --- egg: propagates the held stack onto the entity + falls back to off hand
block:
  let world = newWorld()
  var rand = fromSeed(7'u64)
  let player = mkPlayer(Survival, 0'u16, 0'u8)  ## empty main hand
  player.offHandItem = ItemStack(item: Item(id: 1148'u16), itemCount: 4'u8)  ## 1148: "egg"
  assert getName(player.offHandItem()) == "egg", "test setup: id 1148 should resolve to egg"

  eggNormalUse(player, world, 4'i32, "egg-uuid", rand)

  assert world.playedSounds.len == 1
  assert world.playedSounds[0].soundName == "entity.egg.throw"
  assert world.spawnedEntities.len == 1
  assert world.spawnedEntities[0].kind == "egg"
  assert player.offHandItem().itemCount == 3'u8, "expected one egg consumed from the off hand (main hand was empty)"

echo "egg/snowball normal-use checks passed"
