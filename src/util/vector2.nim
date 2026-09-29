## 2-dimensional vector with generic numeric components.
## Port of upstream/util/src/math/vector2.rs
##
## Rust's `Vector2<T>` is generic over any type implementing its local
## `Math` trait (`+ - * / neg`), blanket-impl'd for f32/f64/i8/i32/i64.
## Nimony supports constrained generics (`proc f[T: SomeConcept]`), and
## built-in arithmetic ops already work generically over any numeric type,
## so this ports as a real generic rather than being monomorphized.
## Skipped: the `serde::Serialize` impl and the `vector_codec_impl!`
## macro-generated `Encode`/`Decode`/`FlatTryFrom` impls (depend on the
## still-unported `codecs` codec layer).

import std/math

type
  Vector2*[T: Arithmetic] = object
    x*: T
    y*: T

proc vec2*[T: Arithmetic](x, y: T): Vector2[T] {.inline.} =
  Vector2[T](x: x, y: y)

proc lengthSquared*[T: Arithmetic](v: Vector2[T]): T {.inline.} =
  v.x * v.x + v.y * v.y

proc add*[T: Arithmetic](a, b: Vector2[T]): Vector2[T] {.inline.} =
  Vector2[T](x: a.x + b.x, y: a.y + b.y)

proc addRaw*[T: Arithmetic](v: Vector2[T], x, y: T): Vector2[T] {.inline.} =
  Vector2[T](x: v.x + x, y: v.y + y)

proc sub*[T: Arithmetic](a, b: Vector2[T]): Vector2[T] {.inline.} =
  Vector2[T](x: a.x - b.x, y: a.y - b.y)

proc multiply*[T: Arithmetic](v: Vector2[T], x, y: T): Vector2[T] {.inline.} =
  Vector2[T](x: v.x * x, y: v.y * y)

proc `*`*[T: Arithmetic](v: Vector2[T], scalar: T): Vector2[T] {.inline.} =
  Vector2[T](x: v.x * scalar, y: v.y * scalar)

proc `+`*[T: Arithmetic](a, b: Vector2[T]): Vector2[T] {.inline.} =
  Vector2[T](x: a.x + b.x, y: a.y + b.y)

proc `-`*[T: Arithmetic](v: Vector2[T]): Vector2[T] {.inline.} =
  Vector2[T](x: -v.x, y: -v.y)

proc length*(v: Vector2[float32]): float32 {.inline.} =
  sqrt(lengthSquared(v))

proc length*(v: Vector2[float64]): float64 {.inline.} =
  sqrt(lengthSquared(v))

proc normalize*(v: Vector2[float32]): Vector2[float32] =
  let r = 1'f32 / length(v)
  if not isNaN(r) and r != Inf and r != -Inf and r > 0'f32:
    Vector2[float32](x: v.x * r, y: v.y * r)
  else:
    Vector2[float32](x: 0, y: 0)

proc normalize*(v: Vector2[float64]): Vector2[float64] =
  let r = 1'f64 / length(v)
  if not isNaN(r) and r != Inf and r != -Inf and r > 0'f64:
    Vector2[float64](x: v.x * r, y: v.y * r)
  else:
    Vector2[float64](x: 0, y: 0)

proc toChunkPos*(v: Vector2[int32]): Vector2[int32] {.inline.} =
  ## Converts a block position vector to a chunk position vector.
  Vector2[int32](x: v.x shr 4, y: v.y shr 4)
