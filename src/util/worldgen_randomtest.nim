## Verifies worldgen_random.nim against upstream's own `#[cfg(test)]`
## vectors in random/worldgen_random.rs (`decoration_seed_matches_vanilla`,
## `dry_grass_modifier_draws_match_vanilla`), which are themselves checked
## against real vanilla Minecraft output.
## Run with `nimony c -r src/util/worldgen_randomtest.nim`.

import std/assertions
import std/syncio
import worldgen_random

const Seed = 1786192857164469025'u64

block decorationSeedMatchesVanilla:
  let chunk86 = getPopulationSeed(Seed, 86'i32 shl 4, 600'i32 shl 4)
  let chunk87 = getPopulationSeed(Seed, 87'i32 shl 4, 600'i32 shl 4)
  assert chunk86 == 0x36e9895dda2bad81'u64, "chunk_86 population seed mismatch"
  assert chunk87 == 0xcdc9553de86a6171'u64, "chunk_87 population seed mismatch"
  assert getDecoratorSeed(chunk86, 69, 9) == 0x36e9895dda2d0d56'u64, "chunk_86 decorator seed mismatch"
  assert getDecoratorSeed(chunk87, 69, 9) == 0xcdc9553de86bc146'u64, "chunk_87 decorator seed mismatch"
  echo "decorationSeedMatchesVanilla: OK"

block dryGrassModifierDrawsMatchVanilla:
  var chunk86 = fromSeed(0x36e9895dda2d0d56'u64)
  assert cast[uint32](nextF32(chunk86)) == 0x3db2ba18'u32, "chunk_86 next_f32 bits mismatch"
  assert nextBoundedI32(chunk86, 16) == 10'i32
  assert nextBoundedI32(chunk86, 16) == 6'i32
  let draws = [nextBoundedI32(chunk86, 8), nextBoundedI32(chunk86, 8),
               nextBoundedI32(chunk86, 4), nextBoundedI32(chunk86, 4),
               nextBoundedI32(chunk86, 8), nextBoundedI32(chunk86, 8)]
  assert draws == [6'i32, 5, 1, 3, 7, 7], "chunk_86 draws mismatch"

  var chunk87 = fromSeed(0xcdc9553de86bc146'u64)
  assert cast[uint32](nextF32(chunk87)) == 0x3f64187a'u32, "chunk_87 next_f32 bits mismatch"
  echo "dryGrassModifierDrawsMatchVanilla: OK"

echo "all worldgen_random checks passed"
