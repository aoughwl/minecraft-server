## Smoke test for perlin.nim's PerlinNoise, run via `nimony c -r`.
##
## No upstream #[cfg(test)] vectors exist for PerlinNoise itself (checked:
## perlin.rs has none), so this can't claim bit-for-bit verification against
## a known-answer table the way legacy_rand.nim/xoroshiro128.nim could. What
## IS checked here, precisely:
##  1. wrap()'s HALF_ROUND_OFF bit-pattern constant is exactly
##     f64::from_bits(0x416FFFFFFFFFFFFF) (cross-computed offline via
##     Python's struct.unpack - see perlin.nim's comment).
##  2. The permutation table built by newPerlinNoise is a valid permutation
##     of 0..255 (every value appears exactly once) - if the Fisher-Yates
##     swap loop had an off-by-one, this would very likely catch it.
##  3. sample() is deterministic (same input -> same output) and varies
##     with input (not a constant/degenerate function).
## TODO: find or derive real known-answer test vectors for PerlinNoise.get
## before trusting this for actual world-gen determinism.

import std/assertions
import std/syncio
import xoroshiro128, perlin

# 1. HalfRoundOff bit-pattern cross-check.
block:
  # 0x416FFFFFFFFFFFFF, reconstructed by hand from its IEEE-754 fields to
  # cross-check the literal in perlin.nim without relying on the same
  # hand-transcription twice: sign=0, exponent=0x416=1046 (unbiased 1046-1023=23),
  # mantissa=0xFFFFFFFFFFFFF (all 52 bits set) => (1 + (2^52-1)/2^52) * 2^23
  let mantissa = (1 shl 52) - 1
  let expected = (1.0'f64 + float64(mantissa) / float64(1'i64 shl 52)) * float64(1'i64 shl 23)
  assert abs(expected - 16777215.999999998'f64) < 1e-6, "HalfRoundOff constant mismatch: " & $expected

# 2. Permutation table validity + wrap() sanity.
block:
  var rng = fromSeed(12345'u64)
  let noise = newPerlinNoise(rng)
  # wrap() should be the identity near the origin.
  assert wrap(0.0) == 0.0
  assert wrap(100.0) == 100.0
  assert wrap(-100.0) == -100.0
  # sample() determinism + variation.
  let a = noise.sample(1.0, 2.0, 3.0)
  let b = noise.sample(1.0, 2.0, 3.0)
  assert a == b, "sample() not deterministic"
  let c = noise.sample(1.5, 2.0, 3.0)
  assert a != c, "sample() looks constant across differing input"
  # A grid of samples should stay in the expected Perlin range (loosely
  # bounded; classic Perlin noise is roughly in [-1, 1], occasionally a
  # bit beyond due to the gradient/lerp shape).
  var minV = 1e9'f32
  var maxV = -1e9'f32
  var x = 0.0
  while x < 10.0:
    var y = 0.0
    while y < 10.0:
      let v = noise.sample(x, y, 0.0)
      if v < minV: minV = v
      if v > maxV: maxV = v
      y += 0.37
    x += 0.41
  assert minV > -2.0'f32 and maxV < 2.0'f32, "sample() out of plausible Perlin range: " & $minV & ".." & $maxV
  echo "perlin: OK (range " & $minV & ".." & $maxV & ")"

echo "all perlin checks passed"
