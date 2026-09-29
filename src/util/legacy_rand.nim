## Legacy (pre-1.13) Java-`Random`-compatible 48-bit LCG.
## Port of upstream/util/src/random/legacy_rand.rs
##
## Ported as a standalone concrete type rather than against Rust's
## `RandomImpl`/`GaussianGenerator` traits and the `RandomGenerator`/
## `RandomDeriver` sum-type enums that unify it with `Xoroshiro`/
## `WorldgenRandom` - those aren't ported yet. `RandomDeriver`'s role
## (choosing between a `LegacySplitter` and an `XoroshiroSplitter`) is
## deferred until xoroshiro128.rs is ported; `LegacySplitter` here always
## produces a `LegacyRand`, matching what upstream's `split_string`/
## `split_u64`/`split_pos` actually do when starting from a `LegacyRand`.
##
## Nimony's `+`/`*`/`-` on signed integers compile straight to the
## underlying C operation with no runtime overflow check available (Nimony
## has no Nim-compatible exceptions to report one through), so they already
## have Rust's `wrapping_add`/`wrapping_mul`/`wrapping_sub` semantics here -
## no separate wrapping variant needed.

import std/math

type
  LegacyRand* = object
    seed: uint64
    hasStoredGaussian: bool
    storedGaussian: float64

  LegacySplitter* = object
    seed*: uint64

proc javaStringHash*(s: string): int32 =
  ## Java's `String.hashCode()`, computed over UTF-16 code units (matches
  ## `str.encode_utf16()` upstream). ASCII-only input (the only case this
  ## port currently needs - resource/registry names) has one UTF-16 code
  ## unit per byte, so this iterates bytes directly rather than pulling in
  ## a UTF-16 encoder; TODO revisit if a non-ASCII split_string key shows up.
  result = 0'i32
  for ch in s:
    result = 31'i32 * result + int32(ch)

proc hashBlockPos*(x, y, z: int32): int64 =
  var l = (int64(x) * 3129871'i64) xor (int64(z) * 116129781'i64) xor int64(y)
  l = l * l * 42317861'i64 + l * 11'i64
  l shr 16

proc fromSeed*(seed: uint64): LegacyRand =
  LegacyRand(seed: (seed xor 0x0005_DEEC_E66D'u64) and 0xFFFF_FFFF_FFFF'u64,
             hasStoredGaussian: false, storedGaussian: 0.0)

proc nextRandom(r: var LegacyRand): int64 =
  let l = cast[int64](r.seed)
  let m = (l * 0x0005_DEEC_E66D'i64 + 11'i64) and 0xFFFFFFFFFFFF'i64
  r.seed = cast[uint64](m)
  m

proc nextBits(r: var LegacyRand, bits: int): int32 =
  int32(nextRandom(r) shr (48 - bits))

proc nextI32*(r: var LegacyRand): int32 =
  nextBits(r, 32)

proc nextBoundedI32*(r: var LegacyRand, bound: int32): int32 =
  if (bound and (bound - 1'i32)) == 0'i32:
    return int32((int64(bound) * int64(nextBits(r, 31))) shr 31)
  while true:
    let i = nextBits(r, 31)
    let j = i mod bound
    if (i - j + (bound - 1'i32)) >= 0'i32:
      return j

proc nextInbetweenI32*(r: var LegacyRand, minV, maxV: int32): int32 =
  if minV >= maxV:
    minV
  else:
    nextBoundedI32(r, maxV - minV + 1'i32) + minV

proc nextInbetweenI32Exclusive*(r: var LegacyRand, minV, maxV: int32): int32 =
  if minV >= maxV:
    minV
  else:
    minV + nextBoundedI32(r, maxV - minV)

proc nextInbetweenF32*(r: var LegacyRand, minV, maxV: float32): float32 =
  nextF32(r) * (maxV - minV) + minV

proc nextI64*(r: var LegacyRand): int64 =
  let i = nextI32(r)
  let j = nextI32(r)
  (int64(i) shl 32) + int64(j)

proc nextBool*(r: var LegacyRand): bool =
  nextBits(r, 1) != 0

proc nextF32*(r: var LegacyRand): float32 =
  float32(nextBits(r, 24)) * 5.9604645e-8'f32

proc nextF64*(r: var LegacyRand): float64 =
  let i = nextBits(r, 26)
  let j = nextBits(r, 27)
  let l = (int64(i) shl 27) + int64(j)
  float64(l) * float64(1.110223e-16'f32)

proc nextTriangular*(r: var LegacyRand, mode, deviation: float64): float64 =
  mode + deviation * (nextF64(r) - nextF64(r))

proc nextGaussian*(r: var LegacyRand): float64 =
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

proc skip*(r: var LegacyRand, count: int32) =
  ## Overridden to match upstream: `next_i64()` consumes two LCG steps, so
  ## skipping must step `next_i32()` exactly `count` times, not `next_i64()`.
  for i in 0'i32 ..< count:
    discard nextI32(r)

proc split*(r: var LegacyRand): LegacyRand =
  fromSeed(cast[uint64](nextI64(r)))

proc newSplitter*(r: var LegacyRand): LegacySplitter =
  LegacySplitter(seed: cast[uint64](nextI64(r)))

proc splitString*(s: LegacySplitter, seed: string): LegacyRand =
  let stringHash = javaStringHash(seed)
  fromSeed(cast[uint64](stringHash) xor s.seed)

proc splitU64*(s: LegacySplitter, seed: uint64): LegacyRand =
  fromSeed(seed)

proc splitPos*(s: LegacySplitter, x, y, z: int32): LegacyRand =
  let posHash = hashBlockPos(x, y, z)
  fromSeed(cast[uint64](posHash) xor s.seed)

proc getPopulationSeed*(worldSeed: uint64, blockX, blockZ: int32): uint64 =
  var rand = fromSeed(worldSeed)
  let l = nextI64(rand) or 1'i64
  let m = nextI64(rand) or 1'i64
  let base = int64(blockX) * l + int64(blockZ) * m
  cast[uint64](base) xor worldSeed
