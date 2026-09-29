## Exercises ThrownItemEntity/SnowballEntity construction and velocity math.
##
## Like dyetest.nim, this transitively imports entity.nim, so per the
## documented finding in entity.nim/README.md ("nothing that imports
## entity.nim can currently be runtime-verified via `nimony c -r`"), this
## is `nimony check`-clean and correct by inspection/hand-computation
## below, NOT proven by actually running it.

import std/math
import std/assertions
import std/syncio
import entity
import projectile
import snowball
import ../../util/vector3
import ../../util/legacy_rand

proc approxEq(a, b: float64, eps = 1e-9): bool =
  abs(a - b) < eps

block basic_construction:
  let owner = newEntity(1'i32, "owner-uuid", EntityDimensions(width: 0.6f32, height: 1.8f32, eyeHeight: 1.62f32))
  owner.pos = vec3(0.0, 64.0, 0.0)
  let e = newEntity(2'i32, "snowball-uuid", EntityDimensions(width: 0.25f32, height: 0.25f32, eyeHeight: 0.125f32))
  let snow = newSnowballEntityShot(e, owner)
  assert snow.thrown.gravity == 0.03
  let (hasOwner, ownerId) = getOwnerId(snow.thrown)
  assert hasOwner and ownerId == 1'i32
  # Spawn position: owner pos + eye height - 0.1, matching ThrownItemEntity::new.
  assert approxEq(e.pos.y, 64.0 + 1.62 - 0.1)
  # Both constructors additionally force velocity to (0, 0.1, 0) after the
  # base construction, matching SnowballEntity::new{,_shot}.
  assert e.velocity == vec3(0.0, 0.1, 0.0)

block set_velocity_direction:
  # Pure hand-check of setVelocity's rotation math: firing straight along
  # +z with zero uncertainty (no jitter) should normalize to yaw/pitch 0.
  let e = newEntity(3'i32, "u", EntityDimensions(width: 0.25f32, height: 0.25f32, eyeHeight: 0.0f32))
  var thrown = newThrownItemEntityNoOwner(e, 0.03)
  var rng = fromSeed(42'u64)
  setVelocity(thrown, rng, 0.0, 0.0, 1.0, 1.5, 0.0)
  # With zero uncertainty, the jitter terms are exactly 0, so velocity is
  # (0,0,1) normalized * power = (0, 0, 1.5).
  assert approxEq(e.velocity.x, 0.0)
  assert approxEq(e.velocity.y, 0.0)
  assert approxEq(e.velocity.z, 1.5)
  assert approxEq(float64(e.yaw), 0.0)
  assert approxEq(float64(e.pitch), 0.0)

block set_velocity_from_matches_manual:
  # setVelocityFrom(pitch=0, yaw=0, roll=0, speed, 0) should reduce to the
  # same straight-+z-ish direction as set_velocity's own trig would give
  # for yaw=0/pitch=0: x = -sin(0)*cos(0) = 0, y = -sin(0) = 0, z = cos(0)*cos(0) = 1.
  let e = newEntity(4'i32, "u", EntityDimensions(width: 0.25f32, height: 0.25f32, eyeHeight: 0.0f32))
  var thrown = newThrownItemEntityNoOwner(e, 0.03)
  var rng = fromSeed(7'u64)
  setVelocityFrom(thrown, rng, 0.0'f32, 0.0'f32, 0.0'f32, 2.0'f32, 0.0'f32)
  assert approxEq(e.velocity.x, 0.0)
  assert approxEq(e.velocity.y, 0.0)
  assert approxEq(e.velocity.z, 2.0)

echo "projectile velocity math checks passed (by inspection - see file header)"
