## Tests tnt.nim's NBT round-trip. Constructs a `TNTEntity`/`Entity`,
## so it's subject to the same closures-through-vtables crash as
## everything else touching entity.nim (NIMONY-COMPILER-BUGS.md #1) -
## check-verified only. See `randomshortfusetest.nim` for the pure-math
## piece, isolated from `entity.nim` so it's genuinely runtime-proven.

import std/[assertions, syncio]
import ../../nbt/tag
import entity
import tnt

block nbtRoundTripBlock:
  let e = Entity(entityUuid: "tnt-1")
  let t = newTNTEntity(e, 6.5'f32, 42'u32)
  var nbt = newCompound()
  let base = tntBaseOf(t)
  base.writeCustomNbtImpl(nbt)

  let t2 = newTNTEntity(Entity(entityUuid: "tnt-2"), TntDefaultPower, TntDefaultFuse)
  let base2 = tntBaseOf(t2)
  base2.readCustomNbtImpl(nbt)
  assert t2.fuse == 42'u32, "expected fuse to round-trip"
  assert abs(t2.power - 6.5'f32) < 1e-5'f32, "expected non-default power to round-trip"

  ## Default power should NOT be written (upstream's epsilon check).
  let (foundPower, _) = get(nbt, "explosion_power")
  assert foundPower, "sanity: non-default power was written"

  var nbtDefault = newCompound()
  let tDefault = newTNTEntity(Entity(entityUuid: "tnt-3"), TntDefaultPower, 5'u32)
  let baseDefault = tntBaseOf(tDefault)
  baseDefault.writeCustomNbtImpl(nbtDefault)
  let (foundDefaultPower, _) = get(nbtDefault, "explosion_power")
  assert not foundDefaultPower, "expected default power to be omitted from NBT"

  echo "tnt NBT round-trip: all checks passed"
