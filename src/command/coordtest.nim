## Exercises coordinates.nim/blockposarg.nim/vec3arg.nim/angle.nim against
## upstream's own documented examples (see each `.rs` file's `examples()`
## list).
##
## Expected but NOT ACHIEVED: real `nimony c -r` proof. This file avoids
## importing argtype.nim, but coordinates.nim (and therefore this file,
## transitively) imports cmdsource.nim for `CommandSource`, and
## `CommandSource` itself is a manual-vtable ref object with `{.closure.}`
## proc fields - so it hits the SAME `eraiser.nim`/`ParamsTagId` crash even
## though `newDummySource()` never sets any of those fields to a real
## closure. That's the 10th confirmation of this bug in the port, and the
## strongest evidence yet for the "reachable in the binary is enough,
## execution isn't required" characterization already noted in
## src/server/entity/README.md: here, not even an *instance* with a
## populated closure field is needed, just the TYPE DEFINITION being
## linked in. So: `nimony check` passes clean (verified), the logic below
## is real and was hand-traced against upstream's examples, but this is
## check-verified only, same as most of the rest of this port.

import std/[syncio, assertions]
import string_reader, cmdsource, coordinates, blockposarg, vec3arg, angle

proc approxEq(a, b: float64, eps = 1e-9): bool =
  abs(a - b) < eps

let source = newDummySource() # position (0,0,0), rotation (0,0)

block blockPosTests:
  var r1 = newStringReader("1 3 5")
  let p1 = parseBlockPos(r1)
  assert p1.isOk
  assert resolveBlockPos(p1.value, source) == (1'i32, 3'i32, 5'i32)

  var r2 = newStringReader("-3 ~24 ~-1")
  let p2 = parseBlockPos(r2)
  assert p2.isOk
  assert resolveBlockPos(p2.value, source) == (-3'i32, 24'i32, -1'i32)

  var r3 = newStringReader("^ ^9 ^56")
  let p3 = parseBlockPos(r3)
  assert p3.isOk
  let v3 = resolve(p3.value, source)
  assert approxEq(v3.y, 9.0) # up-component, independent of rotation math

  assert isValidBlockPos(0, 0, 0)
  assert not isValidBlockPos(30_000_001, 0, 0)
  echo "blockPos: OK"

block vec3Tests:
  var r1 = newStringReader("0 0 0")
  let p1 = parseVec3(r1, true)
  assert p1.isOk
  let v1 = resolveVec3(p1.value, source)
  assert approxEq(v1.x, 0.0) and approxEq(v1.y, 0.0) and approxEq(v1.z, 0.0)

  var r2 = newStringReader("~ ~ ~")
  let p2 = parseVec3(r2, true)
  assert p2.isOk
  let v2 = resolveVec3(p2.value, source)
  assert approxEq(v2.x, 0.0) and approxEq(v2.y, 0.0) and approxEq(v2.z, 0.0)

  var r3 = newStringReader("0.1 -0.5 .9")
  let p3 = parseVec3(r3, true)
  assert p3.isOk
  let v3 = resolveVec3(p3.value, source)
  assert approxEq(v3.x, 0.1) and approxEq(v3.y, -0.5) and approxEq(v3.z, 0.9)

  # centering: an integral, non-relative coordinate gets +0.5 when
  # centerIntegers is true.
  var r4 = newStringReader("1 2 3")
  let p4 = parseVec3(r4, true)
  assert p4.isOk
  let v4 = resolveVec3(p4.value, source)
  assert approxEq(v4.x, 1.5) and approxEq(v4.y, 2.5) and approxEq(v4.z, 3.5)
  echo "vec3: OK"

block angleTests:
  var r1 = newStringReader("0")
  let a1 = parseAngle(r1)
  assert a1.isOk
  assert a1.value.angle == 0.0'f32
  assert not a1.value.isRelative

  var r2 = newStringReader("~")
  let a2 = parseAngle(r2)
  assert a2.isOk
  assert a2.value.isRelative
  assert a2.value.angle == 0.0'f32

  var r3 = newStringReader("~-5")
  let a3 = parseAngle(r3)
  assert a3.isOk
  assert a3.value.isRelative
  assert a3.value.angle == -5.0'f32
  echo "angle: OK"

echo "all coordinate/angle tests passed"
