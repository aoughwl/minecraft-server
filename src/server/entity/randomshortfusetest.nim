## Isolated test for tnt.nim's `randomShortFuse` - deliberately does NOT
## import entity.nim/tnt.nim (which would pull in the closures-through-
## vtables crash, NIMONY-COMPILER-BUGS.md #1), just the pure math
## inlined here. Genuinely runtime-proven via `nimony c -r`, matching
## experienceorb.nim's `orbsizetest.nim` precedent for isolating a pure
## function from its EntityBase-touching neighbors.

import std/[assertions, syncio]
import ../../util/legacy_rand

proc randomShortFuse(fuse: uint32, rng: var LegacyRand): uint32 =
  let bound = max(fuse div 4, 1'u32)
  uint32(nextBoundedI32(rng, int32(bound))) + fuse div 8

var rng = fromSeed(42'u64)
for i in 0 ..< 100:
  let fuse = randomShortFuse(80'u32, rng)
  ## bound = max(80/4, 1) = 20; result in [0+80/8, 19+80/8] = [10, 29]
  assert fuse >= 10'u32 and fuse <= 29'u32, "fuse " & $fuse & " out of expected range"

var rng2 = fromSeed(1'u64)
let zeroFuse = randomShortFuse(0'u32, rng2)
assert zeroFuse == 0'u32, "expected zero fuse to stay zero"

echo "tnt randomShortFuse: all range checks passed"
