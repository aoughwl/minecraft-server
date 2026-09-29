## 3-dimensional vector with generic numeric components.
## Port of upstream/util/src/math/vector3.rs
##
## As with vector2.nim, Rust's local `Math` trait becomes Nimony's built-in
## `std/math.Arithmetic` concept so this stays a real generic instead of
## being monomorphized.
##
## Skipped for now (TODO): `is_within_bounds` (needs a full comparator set
## the concept doesn't require), `sign` (returns `Vector3[int32]` from any
## `T`, i.e. cross-type - needs per-instantiation zero/compare, revisit with
## a concrete-type overload set once a caller needs it), `Into<f64>`/
## `Into<f32>` conversion methods, all serde impls, and the
## `vector_codec_impl!` macro-generated Encode/Decode/FlatTryFrom impls
## (depend on the unported codecs). `BlockPos` interop
## (`is_within_bounds`'s `block_pos: Self` param, `From`/dot with
## `super::position::BlockPos`) is deferred until src/util/position.nim
## exists.

import std/math

type
  Axis* = enum
    axisX
    axisY
    axisZ

  Vector3*[T: Arithmetic] = object
    x*: T
    y*: T
    z*: T

proc axisAll*(): array[3, Axis] {.inline.} =
  [axisY, axisX, axisZ]

proc axisHorizontal*(): array[2, Axis] {.inline.} =
  [axisX, axisZ]

proc axisExcluding*(axis: Axis): array[2, Axis] =
  case axis
  of axisX: [axisY, axisZ]
  of axisY: [axisX, axisZ]
  of axisZ: [axisX, axisY]

proc vec3*[T: Arithmetic](x, y, z: T): Vector3[T] {.inline.} =
  Vector3[T](x: x, y: y, z: z)

proc getAxis*[T: Arithmetic](v: Vector3[T], a: Axis): T {.inline.} =
  case a
  of axisX: v.x
  of axisY: v.y
  of axisZ: v.z

proc setAxis*[T: Arithmetic](v: var Vector3[T], a: Axis, value: T) {.inline.} =
  case a
  of axisX: v.x = value
  of axisY: v.y = value
  of axisZ: v.z = value

proc lengthSquared*[T: Arithmetic](v: Vector3[T]): T {.inline.} =
  v.x * v.x + v.y * v.y + v.z * v.z

proc horizontalLengthSquared*[T: Arithmetic](v: Vector3[T]): T {.inline.} =
  v.x * v.x + v.z * v.z

proc add*[T: Arithmetic](a, b: Vector3[T]): Vector3[T] {.inline.} =
  Vector3[T](x: a.x + b.x, y: a.y + b.y, z: a.z + b.z)

proc addRaw*[T: Arithmetic](v: Vector3[T], x, y, z: T): Vector3[T] {.inline.} =
  Vector3[T](x: v.x + x, y: v.y + y, z: v.z + z)

proc sub*[T: Arithmetic](a, b: Vector3[T]): Vector3[T] {.inline.} =
  Vector3[T](x: a.x - b.x, y: a.y - b.y, z: a.z - b.z)

proc subRaw*[T: Arithmetic](v: Vector3[T], x, y, z: T): Vector3[T] {.inline.} =
  Vector3[T](x: v.x - x, y: v.y - y, z: v.z - z)

proc multiply*[T: Arithmetic](v: Vector3[T], x, y, z: T): Vector3[T] {.inline.} =
  Vector3[T](x: v.x * x, y: v.y * y, z: v.z * z)

proc lerp*[T: Arithmetic](a, b: Vector3[T], t: T): Vector3[T] =
  Vector3[T](
    x: a.x + (b.x - a.x) * t,
    y: a.y + (b.y - a.y) * t,
    z: a.z + (b.z - a.z) * t,
  )

proc squaredDistanceTo*[T: Arithmetic](v: Vector3[T], x, y, z: T): T =
  let dx = v.x - x
  let dy = v.y - y
  let dz = v.z - z
  dx * dx + dy * dy + dz * dz

proc squaredDistanceToVec*[T: Arithmetic](a, b: Vector3[T]): T {.inline.} =
  squaredDistanceTo(a, b.x, b.y, b.z)

proc squaredDistanceToXz*[T: Arithmetic](v: Vector3[T], x, z: T): T =
  let dx = v.x - x
  let dz = v.z - z
  dx * dx + dz * dz

proc squaredDistanceToVecXz*[T: Arithmetic](a, b: Vector3[T]): T {.inline.} =
  squaredDistanceToXz(a, b.x, b.z)

proc dot*[T: Arithmetic](a, b: Vector3[T]): T {.inline.} =
  a.x * b.x + a.y * b.y + a.z * b.z

proc cross*[T: Arithmetic](a, b: Vector3[T]): Vector3[T] {.inline.} =
  Vector3[T](
    x: a.y * b.z - a.z * b.y,
    y: a.z * b.x - a.x * b.z,
    z: a.x * b.y - a.y * b.x,
  )

proc `*`*[T: Arithmetic](v: Vector3[T], scalar: T): Vector3[T] {.inline.} =
  Vector3[T](x: v.x * scalar, y: v.y * scalar, z: v.z * scalar)

proc `/`*[T: Arithmetic](v: Vector3[T], scalar: T): Vector3[T] {.inline.} =
  Vector3[T](x: v.x / scalar, y: v.y / scalar, z: v.z / scalar)

proc `+`*[T: Arithmetic](a, b: Vector3[T]): Vector3[T] {.inline.} =
  Vector3[T](x: a.x + b.x, y: a.y + b.y, z: a.z + b.z)

proc `-`*[T: Arithmetic](a, b: Vector3[T]): Vector3[T] {.inline.} =
  Vector3[T](x: a.x - b.x, y: a.y - b.y, z: a.z - b.z)

proc `+=`*[T: Arithmetic](a: var Vector3[T], b: Vector3[T]) {.inline.} =
  a.x = a.x + b.x
  a.y = a.y + b.y
  a.z = a.z + b.z

proc `-`*[T: Arithmetic](v: Vector3[T]): Vector3[T] {.inline.} =
  Vector3[T](x: -v.x, y: -v.y, z: -v.z)

# --- float-only methods ------------------------------------------------

proc length*(v: Vector3[float32]): float32 {.inline.} =
  sqrt(lengthSquared(v))

proc length*(v: Vector3[float64]): float64 {.inline.} =
  sqrt(lengthSquared(v))

proc horizontalLength*(v: Vector3[float32]): float32 {.inline.} =
  sqrt(horizontalLengthSquared(v))

proc horizontalLength*(v: Vector3[float64]): float64 {.inline.} =
  sqrt(horizontalLengthSquared(v))

proc normalize*(v: Vector3[float32]): Vector3[float32] =
  let r = 1'f32 / length(v)
  if not isNaN(r) and r != Inf and r != -Inf and r > 0'f32:
    Vector3[float32](x: v.x * r, y: v.y * r, z: v.z * r)
  else:
    Vector3[float32](x: 0, y: 0, z: 0)

proc normalize*(v: Vector3[float64]): Vector3[float64] =
  let r = 1'f64 / length(v)
  if not isNaN(r) and r != Inf and r != -Inf and r > 0'f64:
    Vector3[float64](x: v.x * r, y: v.y * r, z: v.z * r)
  else:
    Vector3[float64](x: 0, y: 0, z: 0)

proc rotationVector*(pitch, yaw: float64): Vector3[float64] =
  let h = degToRad(pitch)
  let i = degToRad(-yaw)
  let l = cos(h)
  Vector3[float64](x: sin(i) * l, y: -sin(h), z: cos(i) * l)

proc fromYawPitch*(yaw, pitch: float32): Vector3[float64] =
  let yawRad = degToRad(float64(yaw))
  let pitchRad = degToRad(float64(pitch))
  let cosPitch = cos(pitchRad)
  let sinPitch = sin(pitchRad)
  let cosYaw = cos(yawRad)
  let sinYaw = sin(yawRad)
  Vector3[float64](x: -cosPitch * sinYaw, y: -sinPitch, z: cosPitch * cosYaw)

# --- chunk-position packing (Vector3[int32] only) -----------------------

proc packedChunkPos*(v: Vector3[int32]): int64 =
  (int64(v.x) and 0x003F_FFFF'i64) shl 42 or
    (int64(v.z) and 0x003F_FFFF'i64) shl 20 or
    (int64(v.y) and 0xFFFFF'i64)

proc unpackedChunkPos*(packed: int64): Vector3[int32] =
  let x = int32(packed shr 42)
  let y = int32((packed shl 44) shr 44)
  let z = int32((packed shl 22) shr 42)
  Vector3[int32](x: x, y: y, z: z)

proc packedLocal*(v: Vector3[int32]): int16 =
  ## Bits 8-15: X, bits 4-7: Z, bits 0-3: Y.
  let x = int16(v.x)
  let y = int16(v.y)
  let z = int16(v.z)
  (x shl 8) or (z shl 4) or y
