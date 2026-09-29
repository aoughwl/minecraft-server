## Proves the `EntityBase` composition/dispatch actually works, not just
## that it compiles: builds an `Entity`, a `LivingEntity` wrapping it, and
## a `Player` wrapping that, wraps each in its own `EntityBase`, and checks
## that default-method delegation resolves to the right concrete type at
## each level - the exact behavior `getScoreboardName`/`damage`/`getEntity`
## depend on in upstream's real trait.
## Run with: nimony c -r src/server/entity/entitytest.nim
##
## Uses a manual `check`/`fail` pair instead of `std/assertions`' `assert`:
## `assert` (through its raise/exception path) hits a known Nimony
## compiler-internal crash (`eraiser.nim`'s `fnType.tagEnum == ParamsTagId`
## AssertionDefect) once real closures - which this file constructs a lot
## of, via the `EntityBase` vtables - are in scope, a further variant of
## the already-reported closure/proc-type crash family. Filed as feedback;
## this file works around it rather than waiting on the fix.

import std/syncio
import entity

var failures = 0

proc check(cond: bool, label: string) =
  if cond:
    echo "  ok: " & label
  else:
    echo "  FAIL: " & label
    failures += 1

# --- bare Entity (e.g. a dropped item) --------------------------------
let e = newEntity(1, "uuid-bare-entity", EntityDimensions(width: 0.25'f32, height: 0.25'f32, eyeHeight: 0.2125'f32))
let ebEntity = entityBaseOf(e)

check(getEntity(ebEntity) == e, "bare entity: getEntity resolves to itself")
check(getLivingEntity(ebEntity) == nil, "bare entity: getLivingEntity is nil")
check(getPlayer(ebEntity) == nil, "bare entity: getPlayer is nil")
check(getScoreboardName(ebEntity) == "uuid-bare-entity", "bare entity: scoreboard name falls through to UUID")

# --- LivingEntity wrapping an Entity (e.g. a zombie) --------------------
let zombieEntity = newEntity(2, "uuid-zombie", EntityDimensions(width: 0.6'f32, height: 1.95'f32, eyeHeight: 1.74'f32))
let living = LivingEntity(entity: zombieEntity, health: 20.0'f32, maxHealth: 20.0'f32, lastDamageTaken: 0.0'f32)
let ebLiving = livingEntityBaseOf(living)

check(getEntity(ebLiving) == zombieEntity, "living: getEntity resolves to wrapped Entity")
check(getLivingEntity(ebLiving) == living, "living: getLivingEntity resolves to itself")
check(getPlayer(ebLiving) == nil, "living: getPlayer is nil")
check(getScoreboardName(ebLiving) == "uuid-zombie", "living: scoreboard name still falls through to UUID")

let dtype = DamageType(id: "generic")
let damaged = damage(ebLiving, ebLiving, 6.0'f32, dtype)
check(damaged, "living: damage() returns true")
check(living.health == 14.0'f32, "living: health reduced by damage amount")
check(living.lastDamageTaken == 6.0'f32, "living: lastDamageTaken recorded")

# --- Player wrapping a LivingEntity wrapping an Entity ------------------
let playerEntity = newEntity(3, "uuid-player", EntityDimensions(width: 0.6'f32, height: 1.8'f32, eyeHeight: 1.62'f32))
let playerLiving = LivingEntity(entity: playerEntity, health: 20.0'f32, maxHealth: 20.0'f32, lastDamageTaken: 0.0'f32)
let player = Player(livingEntity: playerLiving, gameProfileName: "Notch")
let ebPlayer = playerBaseOf(player)

# Every level of the composition resolves correctly from the top vtable:
check(getEntity(ebPlayer) == playerEntity, "player: getEntity resolves through LivingEntity to Entity")
check(getLivingEntity(ebPlayer) == playerLiving, "player: getLivingEntity resolves to wrapped LivingEntity")
check(getPlayer(ebPlayer) == player, "player: getPlayer resolves to itself")
# Now DOES take the player-name branch, unlike the bare-entity/living cases above.
check(getScoreboardName(ebPlayer) == "Notch", "player: scoreboard name takes the player-name branch")

discard damage(ebPlayer, ebPlayer, 3.0'f32, dtype)
check(playerLiving.health == 17.0'f32, "player: damage reaches the wrapped LivingEntity's health")

# --- NBT round trip through the EntityBase interface ---------------------
import ../../nbt/tag

playerEntity.onGround = true
playerEntity.pos.x = 12.5
playerEntity.pos.y = 64.0
playerEntity.pos.z = -3.25

var nbt = newCompound()
writeNbt(ebPlayer, nbt)
let (foundGround, groundTag) = get(nbt, "OnGround")
check(foundGround and groundTag.kind == ntkByte and groundTag.byteVal == 1'i8,
      "writeNbt: OnGround written through the EntityBase interface")

# Prove it also round-trips into a *different* entity, not just the
# in-memory compound - build a fresh entity, load the compound into it.
let freshEntity = newEntity(4, "uuid-fresh", EntityDimensions(width: 0.6'f32, height: 1.8'f32, eyeHeight: 1.62'f32))
let freshLiving = LivingEntity(entity: freshEntity, health: 20.0'f32, maxHealth: 20.0'f32, lastDamageTaken: 0.0'f32)
let freshPlayer = Player(livingEntity: freshLiving, gameProfileName: "Steve")
let ebFresh = playerBaseOf(freshPlayer)
check(freshEntity.onGround == false, "fresh entity starts with onGround false")

readNbt(ebFresh, nbt)
check(freshEntity.onGround == true, "readNbt: OnGround loaded into a different entity via EntityBase")

if failures == 0:
  echo "entity composition/dispatch: ALL CHECKS PASSED"
else:
  echo "entity composition/dispatch: " & $failures & " CHECK(S) FAILED"
