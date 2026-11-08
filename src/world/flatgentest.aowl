## Actually runs the flat-section generator and verifies real block-state
## ids come out at the right positions - not just that it compiles.

import std/[assertions, syncio]
import flatgen, palette
import ../generated/blockdata

let stoneSection = generateFlatSectionFromDimension("overworld", 5)
let (foundStone, stone) = blockByName("stone")
let (foundAir, air) = blockByName("air")
assert foundStone and foundAir, "stone/air lookup failed"

# y < 5: stone. y >= 5: air.
for y in 0 ..< 16:
  for z in [0, 8, 15]:
    for x in [0, 8, 15]:
      let got = get(stoneSection, x, y, z)
      if y < 5:
        assert got == uint32(stone.defaultStateId),
          "expected stone at y=" & $y & ", got " & $got
      else:
        assert got == uint32(air.defaultStateId),
          "expected air at y=" & $y & ", got " & $got

# nether's default block is netherrack, not stone - confirms the
# dimension-driven wrapper actually reads real NoiseSettings data, not a
# hardcoded block.
let netherSection = generateFlatSectionFromDimension("nether", 3)
let (foundNetherrack, netherrack) = blockByName("netherrack")
assert foundNetherrack
assert get(netherSection, 8, 0, 8) == uint32(netherrack.defaultStateId),
  "nether flat section should use netherrack, real dimension data wasn't read"

echo "flat chunk-section generator: real block ids verified (overworld/stone, nether/netherrack, air boundary)"
