## Verifies the generated src/generated/biome.nim against real known values.
import std/[assertions, syncio]
import ../generated/biome

let n = allBiomes().len
assert n == 67, "expected 67 biomes, got " & $n

let (found, plains) = biomeFromName("minecraft:plains")
assert found
assert plains.hasPrecipitation == true
assert plains.temperature == 0.8'f32
assert plains.downfall == 0.4'f32
assert plains.carvers.len == 3
assert "minecraft:trees_plains" in plains.features

let (foundShort, plains2) = biomeFromName("plains")
assert foundShort
assert plains2.name == "minecraft:plains"

let (missing, _) = biomeFromName("minecraft:not_a_biome")
assert not missing

echo "biome.nim: all checks passed (", n, " biomes)"
