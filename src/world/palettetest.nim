## Smoke test for palette.nim, run via `nimony c -r src/world/palettetest.nim`.
import std/assertions
import std/syncio
import palette

# 16x16x16 block section, default-filled with "air" (id 0).
var p = newPalettedContainer(16, 0'u32)
assert p.paletteSize == 1
assert p.isSingleValued

# Fill every cell with distinct values to force an Indexed->Dense upgrade
# past 255 distinct palette entries (16^3 = 4096 cells > 255).
var expect = newSeq[uint32](16 * 16 * 16)
var n = 0
for y in 0 ..< 16:
  for z in 0 ..< 16:
    for x in 0 ..< 16:
      let v = uint32(n mod 300)  # cycle through 300 distinct ids > 255
      discard p.set(x, y, z, v)
      expect[(y * 16 + z) * 16 + x] = v
      inc n

for y in 0 ..< 16:
  for z in 0 ..< 16:
    for x in 0 ..< 16:
      assert p.get(x, y, z) == expect[(y * 16 + z) * 16 + x]

assert not p.isSingleValued
assert p.paletteSize == 300

# Overwrite everything back to a single value; palette should shrink to 1
# (exercises the swap-remove-on-zero-count path many, many times).
for y in 0 ..< 16:
  for z in 0 ..< 16:
    for x in 0 ..< 16:
      discard p.set(x, y, z, 7'u32)

for y in 0 ..< 16:
  for z in 0 ..< 16:
    for x in 0 ..< 16:
      assert p.get(x, y, z) == 7'u32

assert p.isSingleValued
assert p.paletteSize == 1

# Small biome section (4x4x4), stays in Indexed form the whole time.
var b = newPalettedContainer(4, 1'u32)
discard b.set(1, 2, 3, 5'u32)
assert b.get(1, 2, 3) == 5'u32
assert b.get(0, 0, 0) == 1'u32
assert b.paletteSize == 2

echo "palette.nim: all checks passed"
