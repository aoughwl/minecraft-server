## Round-trip test for chunkdata.nim - actually run, not just checked.
## Verifies the heightmap 9-bit packing against upstream's own bit-shape
## (7 columns/i64 word, no cross-word values) and ChunkSections'
## multi-section block get/set against the underlying PalettedContainer.

import std/[syncio, assertions]
import chunkdata

proc testHeightmaps() =
  var h = newChunkHeightmaps()
  let minY = -64'i32

  # Every column in a 16x16 area, with a distinct height per column so a
  # packing bug (wrong shift/mask/word) would corrupt a neighbor.
  for x in 0'i32 ..< 16:
    for z in 0'i32 ..< 16:
      let height = minY + x * 16 + z + 1
      setHeightmap(h, chmMotionBlocking, x, z, height, minY)

  for x in 0'i32 ..< 16:
    for z in 0'i32 ..< 16:
      let expected = minY + x * 16 + z + 1
      let got = getHeightmap(h, chmMotionBlocking, x, z, minY)
      assert got == expected, "heightmap mismatch at (" & $x & "," & $z & "): got " & $got & " want " & $expected

  # A never-set heightmap type returns minY - 1 (upstream's "unset" sentinel).
  assert getHeightmap(h, chmWorldSurface, 0, 0, minY) == minY - 1

  # Setting one type doesn't disturb another.
  setHeightmap(h, chmWorldSurface, 5, 5, 100, minY)
  assert getHeightmap(h, chmMotionBlocking, 5, 5, minY) == minY + 5 * 16 + 5 + 1
  assert getHeightmap(h, chmWorldSurface, 5, 5, minY) == 100

  echo "heightmap packing: OK"

proc testChunkSections() =
  let minY = -64'i32
  var s = newChunkSections(24, minY, 0'u32, 0'u32) # 24 sections = -64..320

  # Set a distinct block-state id at several points spanning multiple
  # sections (Y=-64 is section 0, Y=319 is section 23) and confirm they
  # read back correctly and don't bleed into neighbors.
  let points = @[
    (0'i32, -64'i32, 0'i32, 111'u32),
    (15'i32, -1'i32, 15'i32, 222'u32),
    (8'i32, 0'i32, 8'i32, 333'u32),
    (3'i32, 319'i32, 3'i32, 444'u32),
  ]
  # Avoid `for (a, b, ...) in seqOfTuples` - a known Nimony gotcha
  # (tuple-destructure over a local seq can mis-bind/crash the parser).
  for i in 0 ..< points.len:
    let p = points[i]
    discard setBlock(s, p[0], p[1], p[2], p[3])

  for i in 0 ..< points.len:
    let p = points[i]
    let got = getBlock(s, p[0], p[1], p[2])
    assert got == p[3], "block mismatch at index " & $i & ": got " & $got & " want " & $p[3]

  # Untouched cell stays at the default.
  assert getBlock(s, 1, 1, 1) == 0'u32

  assert sectionIndex(s, minY) == 0
  assert sectionIndex(s, 319'i32) == 23 # world Y=319 is the top of a -64..319 (24-section) range

  echo "chunk sections block get/set: OK"

testHeightmaps()
testChunkSections()
echo "all chunkdata checks passed"
