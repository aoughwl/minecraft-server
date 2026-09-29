## Verifies gen_mob_variant.nim's output against real source JSON. Run with
## `nimony c -r src/data_codegen/mob_varianttest.nim`.

import std/[syncio, assertions]
import "../generated/cow_variant"
import "../generated/pig_variant"
import "../generated/chicken_variant"
import "../generated/zombie_nautilus_variant"

assert AllCowVariants.len == 3
assert assetId(cvCold) == "minecraft:entity/cow/cow_cold"
assert babyAssetId(cvTemperate) == "minecraft:entity/cow/cow_temperate_baby"
assert model(cvTemperate) == "" # temperate.json has no "model" key
assert model(cvCold) == "cold"
let (foundCow, cv) = cvFromName("minecraft:warm")
assert foundCow and cv == cvWarm
assert toName(cvWarm) == "warm"

assert AllPigVariants.len == 3
assert AllChickenVariants.len == 3
assert AllZombieNautilusVariants.len == 2 # only temperate/warm exist upstream

let (foundZn, znv) = znvFromName("temperate")
assert foundZn and znv == znvTemperate
assert assetId(znvTemperate).len > 0

echo "mob_variant: all checks passed"
