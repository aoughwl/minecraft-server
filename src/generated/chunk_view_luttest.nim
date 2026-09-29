## Verifies chunk_view_lut.nim's tables against upstream's own math, run via
## `nimony c -r src/generated/chunk_view_luttest.nim`.

import std/assertions
import std/syncio
import chunk_view_lut

# dist 0 and 1 are empty per upstream's early return.
assert chunkViewLut[0].len == 0
assert chunkViewLut[1].len == 0
# dist >= 2 must be non-empty and every offset must satisfy the same
# inequality upstream filters by: relX^2 + relZ^2 < d^2.
for dist in 2'u8 .. 10'u8:
  let d = int32(dist)
  assert chunkViewLut[int(dist)].len > 0
  for pos in chunkViewLut[int(dist)]:
    let relX = max(abs(int32(pos[0])) - 2, 0)
    let relZ = max(abs(int32(pos[1])) - 2, 0)
    assert relX * relX + relZ * relZ < d * d

# Chebyshev radius 0 is just the origin.
assert chebyshev.offsets.len == chebyshev.squareEnd[int(MaxChebyshevRadius)]
assert getChebyshevRing(0'u8) == @[(0'i8, 0'i8)]

# Ring r has 8r offsets (r > 0); square radius r has 1 + 4r(r+1) offsets -
# upstream's own concentric-square identity.
for r in 1'u8 .. 5'u8:
  assert getChebyshevRing(r).len == 8 * int(r)
  let expectedSquare = 1 + 4 * int(r) * (int(r) + 1)
  assert getChebyshevSquare(r).len == expectedSquare

# Total offset count at max radius matches the closed-form sum.
var expectedTotal = 1
for r in 1 .. int(MaxChebyshevRadius):
  expectedTotal += 8 * r
assert chebyshev.offsets.len == expectedTotal

echo "chunk_view_lut: all checks passed (" & $chebyshev.offsets.len & " chebyshev offsets)"
