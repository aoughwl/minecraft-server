## Exercises EggEntity/EnderPearlEntity construction, following
## concretetest.nim's split: real assertions on the plain (non-vtable)
## fields, run via `nimony check` only - this file transitively imports
## entity.nim, so `nimony c -r` hits the documented closures-through-
## vtables crash (see NIMONY-COMPILER-BUGS.md #1) regardless of whether
## this file calls a vtable proc itself.

import std/assertions
import std/syncio
import entity
import projectile
import egg
import enderpearl
import ../../util/vector3
import ../../generated/entity_type
import ../../inventory/itemstub

proc realDims(name: string): EntityDimensions =
  let (found, et) = entityTypeByName(name)
  assert found, "expected " & name & " in the generated entity_type table"
  EntityDimensions(width: et.dimensionW, height: et.dimensionH, eyeHeight: et.eyeHeight)

let owner = newEntity(1'i32, "owner-uuid", EntityDimensions(width: 0.6'f32, height: 1.8'f32, eyeHeight: 1.62'f32))
owner.pos = vec3(0.0, 64.0, 0.0)

block egg_construction:
  let e = newEntity(2'i32, "egg-uuid", realDims("egg"))
  let eggEnt = newEggEntityShot(e, owner)
  assert eggEnt.thrown.gravity == 0.03
  assert e.velocity == vec3(0.0, 0.1, 0.0)
  assert eggEnt.itemStack.item.id == 1148'u16
  assert getMaxStackSize(eggEnt.itemStack) == 16'u8, "real egg maxStackSize from src/generated/item.nim"

  let e2 = newEntity(3'i32, "egg-uuid-2", realDims("egg"))
  let eggEnt2 = newEggEntity(e2)
  assert e2.velocity == vec3(0.0, 0.1, 0.0)
  setItemStack(eggEnt2, ItemStack(item: Item(id: 1148'u16), itemCount: 3'u8))
  assert eggEnt2.itemStack.itemCount == 3'u8

block ender_pearl_construction:
  let e = newEntity(4'i32, "pearl-uuid", realDims("ender_pearl"))
  let pearl = newEnderPearlEntityShot(e, owner)
  assert pearl.thrown.gravity == 0.03
  let (hasOwner, ownerId) = getOwnerId(pearl.thrown)
  assert hasOwner and ownerId == 1'i32
  assert e.velocity == vec3(0.0, 0.1, 0.0)

echo "egg/ender_pearl construction checks passed (nimony check only - see file header)"
