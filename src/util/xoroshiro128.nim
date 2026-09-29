## Xoroshiro128+ random number generator - the modern PRNG used by newer
## Minecraft versions for world generation (faster, better statistical
## properties than the legacy LCG in legacy_rand.nim).
## Ported from upstream's random/xoroshiro128.rs.
##
## Ported as a standalone concrete type rather than against Rust's
## `RandomImpl`/`GaussianGenerator` traits and the `RandomGenerator`/
## `RandomDeriver` sum-type enums that unify it with `LegacyRand` - Nimony
## has no trait objects, and unifying the two generators behind one type
## is a real design decision deferred to whoever wires up the full
## `random/mod.rs`. Follows the same convention as legacy_rand.nim.

import std/md5
import std/math

type
  Xoroshiro* = object
    lo, hi: uint64
    hasStoredGaussian: bool
    storedGaussian: float64

  XoroshiroSplitter* = object
    lo, hi: uint64

proc mixStafford13(z0: uint64): uint64 =
  var z = z0
  z = (z xor (z shr 30)) * 0xBF58476D1CE4E5B9'u64
  z = (z xor (z shr 27)) * 0x94D049BB133111EB'u64
  z xor (z shr 31)

proc mixU64(seed: uint64): (uint64, uint64) =
  let l = seed xor 0x6A09E667F3BCC909'u64
  let m = l + 0x9E3779B97F4A7C15'u64
  (l, m)

proc rotl(x: uint64, k: int): uint64 {.inline.} =
  (x shl k) or (x shr (64 - k))

proc newXoroshiro(lo0, hi0: uint64): Xoroshiro =
  var lo = lo0
  var hi = hi0
  if (lo or hi) == 0:
    lo = 0x9E3779B97F4A7C15'u64
    hi = 0x6A09E667F3BCC909'u64
  Xoroshiro(lo: lo, hi: hi, hasStoredGaussian: false, storedGaussian: 0.0)

proc fromSeed*(seed: uint64): Xoroshiro =
  let (lo0, hi0) = mixU64(seed)
  newXoroshiro(mixStafford13(lo0), mixStafford13(hi0))

proc fromSeedUnmixed*(seed: uint64): Xoroshiro =
  let (lo0, hi0) = mixU64(seed)
  newXoroshiro(lo0, hi0)

proc nextRandom(r: var Xoroshiro): uint64 =
  let l = r.lo
  let m = r.hi
  let n = rotl(l + m, 17) + l
  let m2 = m xor l
  r.lo = rotl(l, 49) xor m2 xor (m2 shl 21)
  r.hi = rotl(m2, 28)
  n

proc nextBits(r: var Xoroshiro, bits: int): uint64 {.inline.} =
  nextRandom(r) shr (64 - bits)

proc nextI32*(r: var Xoroshiro): int32 =
  cast[int32](nextRandom(r) and 0xFFFFFFFF'u64)

proc nextBoundedI32*(r: var Xoroshiro, bound: int32): int32 =
  var l = uint64(cast[uint32](nextI32(r)))
  var m = l * uint64(bound)
  var n = m and 0xFFFFFFFF'u64
  if n < uint64(bound):
    let i = uint64(cast[uint32]((not bound) + 1'i32)) mod uint64(bound)
    while n < i:
      l = uint64(cast[uint32](nextI32(r)))
      m = l * uint64(bound)
      n = m and 0xFFFFFFFF'u64
  cast[int32](uint32(m shr 32))

proc nextInbetweenI32*(r: var Xoroshiro, minV, maxV: int32): int32 =
  minV + nextBoundedI32(r, maxV - minV + 1)

proc nextInbetweenI32Exclusive*(r: var Xoroshiro, minV, maxV: int32): int32 =
  minV + nextBoundedI32(r, maxV - minV)

proc nextI64*(r: var Xoroshiro): int64 =
  cast[int64](nextRandom(r))

proc nextBool*(r: var Xoroshiro): bool =
  (nextRandom(r) and 1'u64) != 0

proc nextF32*(r: var Xoroshiro): float32 =
  float32(nextBits(r, 24)) * 5.9604645e-8'f32

proc nextF64*(r: var Xoroshiro): float64 =
  # Upstream multiplies by an f32 constant widened to f64 (`f64::from(1.110_223E-16f32)`),
  # not a full-precision f64 literal - replicate that same precision loss.
  float64(nextBits(r, 53)) * float64(1.110223e-16'f32)

proc nextGaussian*(r: var Xoroshiro): float64 =
  ## Same rejection-sampling Box-Muller variant as legacy_rand.nim's
  ## `nextGaussian` (mirrors upstream's shared `GaussianGenerator` trait).
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

proc split*(r: var Xoroshiro): Xoroshiro =
  newXoroshiro(nextRandom(r), nextRandom(r))

proc newSplitter*(r: var Xoroshiro): XoroshiroSplitter =
  XoroshiroSplitter(lo: nextRandom(r), hi: nextRandom(r))

proc splitString*(s: XoroshiroSplitter, seed: string): Xoroshiro =
  let digest = toMD5(seed)
  var l: uint64 = 0
  var m: uint64 = 0
  for i in 0 ..< 8:
    l = (l shl 8) or uint64(digest[i])
  for i in 8 ..< 16:
    m = (m shl 8) or uint64(digest[i])
  newXoroshiro(l xor s.lo, m xor s.hi)

proc fromLoAndHi*(s: XoroshiroSplitter, lo, hi: uint64): Xoroshiro =
  newXoroshiro(lo xor s.lo, hi xor s.hi)

proc hashBlockPos*(x, y, z: int32): int64 =
  ## Same block-position hash as `legacy_rand.nim`'s `hashBlockPos` (both
  ## port the same shared upstream `hash_block_pos` helper).
  var l = (int64(x) * 3129871'i64) xor (int64(z) * 116129781'i64) xor int64(y)
  l = l * l * 42317861'i64 + l * 11'i64
  l shr 16

proc splitPos*(s: XoroshiroSplitter, x, y, z: int32): Xoroshiro =
  let l = cast[uint64](hashBlockPos(x, y, z))
  newXoroshiro(l xor s.lo, s.hi)
