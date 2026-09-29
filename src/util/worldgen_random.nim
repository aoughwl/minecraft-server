## A Xoroshiro source accessed through Java `WorldgenRandom` bit-source
## semantics: `next(bits)` takes the high bits of a complete underlying
## `nextLong()` draw, which differs from Xoroshiro's own direct methods.
## Ported from upstream's random/worldgen_random.rs.

import xoroshiro128
import std/math
import std/assertions

type
  WorldgenRandom* = object
    source: Xoroshiro
    hasStoredGaussian: bool
    storedGaussian: float64

proc fromSeed*(seed: uint64): WorldgenRandom =
  WorldgenRandom(source: xoroshiro128.fromSeed(seed), hasStoredGaussian: false, storedGaussian: 0.0)

proc next(r: var WorldgenRandom, bits: int): uint64 {.inline.} =
  # Xoroshiro's own `next(bits)` is private to its module; reimplement the
  # same `next_random() >> (64 - bits)` shape via the public nextBoundedI32-
  # adjacent surface isn't available, so draw a full next_i64 and shift -
  # matches `WorldgenRandom::next` delegating to `Xoroshiro::next`, which
  # itself is `next_random() >> (64 - bits)`.
  cast[uint64](nextI64(r.source)) shr (64 - bits)

proc nextI32*(r: var WorldgenRandom): int32 =
  cast[int32](next(r, 32) and 0xFFFFFFFF'u64)

proc nextBoundedI32*(r: var WorldgenRandom, bound: int32): int32 =
  assert bound > 0, "bound must be positive"
  if (bound and (bound - 1'i32)) == 0'i32:
    return int32((int64(bound) * int64(next(r, 31))) shr 31)
  while true:
    let value = cast[int32](next(r, 31) and 0x7FFFFFFF'u64)
    let result = value mod bound
    if (value - result + (bound - 1'i32)) >= 0'i32:
      return result

proc nextI64*(r: var WorldgenRandom): int64 =
  let high = nextI32(r)
  let low = nextI32(r)
  (int64(high) shl 32) + int64(low)

proc nextBool*(r: var WorldgenRandom): bool =
  next(r, 1) != 0'u64

proc nextF32*(r: var WorldgenRandom): float32 =
  float32(next(r, 24)) * 5.9604645e-8'f32

proc nextF64*(r: var WorldgenRandom): float64 =
  let high = next(r, 26)
  let low = next(r, 27)
  float64((high shl 27) + low) * 1.1102230246251565e-16'f64

proc nextGaussian*(r: var WorldgenRandom): float64 =
  ## Same rejection-sampling Box-Muller variant as legacy_rand.nim /
  ## xoroshiro128.nim's `nextGaussian`.
  if r.hasStoredGaussian:
    r.hasStoredGaussian = false
    return r.storedGaussian
  while true:
    let d = nextF64(r) * 2.0 - 1.0
    let e = nextF64(r) * 2.0 - 1.0
    let f = d * d + e * e
    if f < 1.0 and f != 0.0:
      let g = sqrt(-2.0 * ln(f) / f)
      r.storedGaussian = e * g
      r.hasStoredGaussian = true
      return d * g

proc split*(r: var WorldgenRandom): WorldgenRandom =
  WorldgenRandom(source: xoroshiro128.split(r.source), hasStoredGaussian: false, storedGaussian: 0.0)

proc getPopulationSeed*(worldSeed: uint64, blockX, blockZ: int32): uint64 =
  var rand = fromSeed(worldSeed)
  let l = nextI64(rand) or 1'i64
  let m = nextI64(rand) or 1'i64
  let base = int64(blockX) * l + int64(blockZ) * m
  cast[uint64](base) xor worldSeed

proc getDecoratorSeed*(populationSeed, index, step: uint64): uint64 =
  populationSeed + index + 10000'u64 * step
