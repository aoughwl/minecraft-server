## Classic value/gradient noise (Improved Perlin Noise), the base layer
## Minecraft's terrain density functions sample through `NormalNoise`.
## Port of upstream's noise/perlin.rs - core `PerlinNoise` (permutation
## table + point sampling via `get`/`sample_and_lerp`) only.
##
## NOT ported this pass: `add_to_volume` (needs the still-unported
## `DensityVolume`), `Corners`/batched-sampling fast path (an optimization
## over the same math `get` already computes correctly, just slower),
## `SmearedPerlinNoise`, `NoiseStack`, `NormalNoise`'s octave-sum/
## normalization-factor machinery, and `legacy_fbm`. Point sampling via
## `sample` is the part that's independently testable and needed first;
## the octave stack builds on top of this without changing its math.

import std/math
import mathlerp

const
  Gradients: array[16, array[3, float32]] = [
    [1.0'f32, 1.0'f32, 0.0'f32],
    [-1.0'f32, 1.0'f32, 0.0'f32],
    [1.0'f32, -1.0'f32, 0.0'f32],
    [-1.0'f32, -1.0'f32, 0.0'f32],
    [1.0'f32, 0.0'f32, 1.0'f32],
    [-1.0'f32, 0.0'f32, 1.0'f32],
    [1.0'f32, 0.0'f32, -1.0'f32],
    [-1.0'f32, 0.0'f32, -1.0'f32],
    [0.0'f32, 1.0'f32, 1.0'f32],
    [0.0'f32, -1.0'f32, 1.0'f32],
    [0.0'f32, 1.0'f32, -1.0'f32],
    [0.0'f32, -1.0'f32, -1.0'f32],
    [1.0'f32, 1.0'f32, 0.0'f32],
    [0.0'f32, -1.0'f32, 1.0'f32],
    [-1.0'f32, 1.0'f32, 0.0'f32],
    [0.0'f32, -1.0'f32, -1.0'f32],
  ]

  RoundOff = 33_554_432.0'f64
  # Rust: f64::from_bits(0x416FFFFFFFFFFFFF), computed offline (verified via
  # Python's struct.unpack('>d', ...)) since Nimony has no f64::from_bits
  # equivalent in the stdlib checked so far. Despite its name this is
  # 16777215.999999998, one ULP below 2^24 = RoundOff/2 - see perlintest.nim.
  HalfRoundOff = 16777215.999999998'f64
  NoiseOffsetScale = 256.0'f64

type
  RandomSource = concept
    proc nextF64(r: var Self): float64
    proc nextBoundedI32(r: var Self, bound: int32): int32

  PerlinNoise* = object
    perms: array[256, uint8]
    offsetX*, offsetY*, offsetZ*: float64

proc wrap*(x: float64): float64 {.inline.} =
  ## Wraps `x` into roughly [-2^24, 2^24) without discontinuities at the
  ## boundary, so repeated octave sampling doesn't walk arbitrarily far
  ## from the origin and lose f64 precision.
  if x > -HalfRoundOff and x < HalfRoundOff:
    x
  else:
    x - floor(x / RoundOff + 0.5) * RoundOff

proc gradDot(hash: int32, x, y, z: float32): float32 {.inline.} =
  let g = Gradients[hash and 15]
  g[0] * x + g[1] * y + g[2] * z

proc newPerlinNoise*[R: RandomSource](random: var R): PerlinNoise {.noinit.} =
  ## `R` needs `nextF64(var R): float64` and `nextBoundedI32(var R, int32): int32`
  ## - both `LegacyRand` and `Xoroshiro` already provide this shape.
  result.offsetX = nextF64(random) * NoiseOffsetScale
  result.offsetY = nextF64(random) * NoiseOffsetScale
  result.offsetZ = nextF64(random) * NoiseOffsetScale
  for i in 0 ..< 256:
    result.perms[i] = uint8(i)
  for i in 0 ..< 256:
    let offset = int(nextBoundedI32(random, int32(256 - i)))
    let j = offset + i
    let tmp = result.perms[i]
    result.perms[i] = result.perms[j]
    result.perms[j] = tmp

proc permute(p: PerlinNoise, x: int32): int32 {.inline.} =
  int32(p.perms[int(x and 0xFF'i32)])

proc sampleAndLerp(p: PerlinNoise, x, y, z: int32,
                    relativeX, relativeY, relativeZ, originalRelativeY: float32): float32 =
  let x0 = p.permute(x)
  let x1 = p.permute(x + 1)
  let xy00 = p.permute(x0 + y)
  let xy01 = p.permute(x0 + y + 1)
  let xy10 = p.permute(x1 + y)
  let xy11 = p.permute(x1 + y + 1)
  let d000 = gradDot(p.permute(xy00 + z), relativeX, relativeY, relativeZ)
  let d100 = gradDot(p.permute(xy10 + z), relativeX - 1.0'f32, relativeY, relativeZ)
  let d010 = gradDot(p.permute(xy01 + z), relativeX, relativeY - 1.0'f32, relativeZ)
  let d110 = gradDot(p.permute(xy11 + z), relativeX - 1.0'f32, relativeY - 1.0'f32, relativeZ)
  let d001 = gradDot(p.permute(xy00 + z + 1), relativeX, relativeY, relativeZ - 1.0'f32)
  let d101 = gradDot(p.permute(xy10 + z + 1), relativeX - 1.0'f32, relativeY, relativeZ - 1.0'f32)
  let d011 = gradDot(p.permute(xy01 + z + 1), relativeX, relativeY - 1.0'f32, relativeZ - 1.0'f32)
  let d111 = gradDot(p.permute(xy11 + z + 1), relativeX - 1.0'f32, relativeY - 1.0'f32, relativeZ - 1.0'f32)
  let alphaX = smoothstep(relativeX)
  let alphaY = smoothstep(originalRelativeY)
  let alphaZ = smoothstep(relativeZ)
  lerp3(alphaX, alphaY, alphaZ, d000, d100, d010, d110, d001, d101, d011, d111)

proc sample*(p: PerlinNoise, x, y, z: float64): float32 =
  let wx = wrap(x) + p.offsetX
  let wy = wrap(y) + p.offsetY
  let wz = wrap(z) + p.offsetZ
  let floorX = int32(floor(wx))
  let floorY = int32(floor(wy))
  let floorZ = int32(floor(wz))
  let relX = float32(wx - float64(floorX))
  let relY = float32(wy - float64(floorY))
  let relZ = float32(wz - float64(floorZ))
  p.sampleAndLerp(floorX, floorY, floorZ, relX, relY, relZ, relY)
