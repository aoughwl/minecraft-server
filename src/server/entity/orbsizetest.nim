## Isolated run of `roundToOrbSize` alone, with NO import of `entity.nim`
## (which defines `EntityBase`'s `{.closure.}` vtable fields) - to check
## whether the runtime crash is triggered merely by a `{.closure.}` field
## existing anywhere in the compiled binary, or only by actually calling
## through one. See concretetest.nim's header for the crash this is
## isolating away from.

import std/syncio
import std/assertions

proc roundToOrbSize(value: uint32): uint32 =
  if value >= 2477: 2477'u32
  elif value >= 1237: 1237'u32
  elif value >= 617: 617'u32
  elif value >= 307: 307'u32
  elif value >= 149: 149'u32
  elif value >= 73: 73'u32
  elif value >= 37: 37'u32
  elif value >= 17: 17'u32
  elif value >= 7: 7'u32
  elif value >= 3: 3'u32
  else: 1'u32

assert roundToOrbSize(10000'u32) == 2477'u32
assert roundToOrbSize(2477'u32) == 2477'u32
assert roundToOrbSize(2476'u32) == 1237'u32
assert roundToOrbSize(5'u32) == 3'u32
assert roundToOrbSize(2'u32) == 1'u32
echo "roundToOrbSize checks passed (isolated from EntityBase's closure vtable)"
