## Port of upstream/pumpkin/src/entity/projectile/mod.rs's `ThrownItemEntity`:
## the shared base state/math every thrown-projectile entity (snowball, egg,
## ender pearl, ...) is built on.
##
## Deliberately NOT ported here: `process_tick`'s block-collision/hit-
## detection sweep and `apply_on_projectile_spawned`'s enchantment hooks -
## both need `World`/`EnchantmentHelper`, which don't exist yet. The
## portable part is the pure velocity math, which is what this file covers.

import std/math
import entity
import ../../util/vector3
import ../../util/legacy_rand

type
  ThrownItemEntity* = object
    ## `owner_id`/`collides_with_projectiles`/`has_hit`/`gravity` mirror
    ## upstream field-for-field; `entity` is embedded like everywhere else
    ## in this composition shape.
    entity*: Entity
    ownerId*: (bool, int32)
    collidesWithProjectiles*: bool
    hasHit*: bool
    gravity*: float64

proc newThrownItemEntity*(e: Entity, owner: Entity, gravity: float64): ThrownItemEntity =
  ## Port of `ThrownItemEntity::new`. Upstream spawns the projectile at the
  ## owner's eye height minus 0.1.
  var ownerPos = owner.pos
  ownerPos.y += float64(owner.dimensions.eyeHeight) - 0.1
  e.pos = ownerPos
  ThrownItemEntity(
    entity: e,
    ownerId: (true, owner.entityId),
    collidesWithProjectiles: false,
    hasHit: false,
    gravity: gravity,
  )

proc newThrownItemEntityNoOwner*(e: Entity, gravity: float64): ThrownItemEntity =
  ## Port of the ownerless construction path (e.g. `SnowballEntity::new`).
  ThrownItemEntity(
    entity: e,
    ownerId: (false, 0'i32),
    collidesWithProjectiles: false,
    hasHit: false,
    gravity: gravity,
  )

proc setVelocity*(t: var ThrownItemEntity, rand: var LegacyRand,
                   x, y, z, power, uncertainty: float64) =
  ## Port of `ThrownItemEntity::set_velocity`. Upstream draws its jitter
  ## from `rand::random::<f64>()` - Rust's unseeded system RNG, not the
  ## world-seeded generator - so this isn't a determinism-sensitive path
  ## the way `legacy_rand.nim`'s other callers are; any uniform random
  ## source is faithful. Takes an explicit `LegacyRand` (rather than a
  ## hidden global) so callers/tests control and can reproduce the draw,
  ## and because no ambient RNG instance exists anywhere in this port yet.
  proc nextTriangularSys(r: var LegacyRand, mode, deviation: float64): float64 =
    deviation * (r.nextF64() - r.nextF64()) + mode

  let jitter = 0.0172275 * uncertainty
  var velocity = vec3(x, y, z).normalize()
  velocity = velocity.addRaw(
    nextTriangularSys(rand, 0.0, jitter),
    nextTriangularSys(rand, 0.0, jitter),
    nextTriangularSys(rand, 0.0, jitter),
  )
  velocity = velocity.multiply(power, power, power)

  t.entity.velocity = velocity
  let len = velocity.horizontalLength()
  # atan2(x, z) matches upstream's `x.atan2(z)` (note the argument order:
  # Rust's `f64::atan2` is `self.atan2(other)` = atan2(self, other)).
  t.entity.yaw = float32(arctan2(velocity.x, velocity.z)) * 57.295776'f32
  t.entity.pitch = float32(arctan2(velocity.y, len)) * 57.295776'f32

proc setVelocityFrom*(t: var ThrownItemEntity, rand: var LegacyRand,
                       pitch, yaw, roll, speed, divergence: float32) =
  ## Port of `ThrownItemEntity::set_velocity_from` (used when a shooter
  ## throws/fires in a given facing direction rather than a raw vector).
  let yawRad = float64(yaw) * (PI / 180.0)
  let pitchRad = float64(pitch) * (PI / 180.0)
  let rollRad = float64(pitch + roll) * (PI / 180.0)

  let x = -sin(yawRad) * cos(pitchRad)
  let y = -sin(rollRad)
  let z = cos(yawRad) * cos(pitchRad)

  setVelocity(t, rand, x, y, z, float64(speed), float64(divergence))

proc getEntity*(t: ThrownItemEntity): Entity {.inline.} = t.entity
proc getGravity*(t: ThrownItemEntity): float64 {.inline.} = t.gravity
proc getOwnerId*(t: ThrownItemEntity): (bool, int32) {.inline.} = t.ownerId
