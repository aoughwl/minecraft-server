## A generic Java-style number, plus the widening/narrowing conversions
## Java's numeric casts use. Port of
## upstream/codecs/src/number.rs
##
## The `serde_json::Value`/`serde_json::Number` conversions at the bottom of
## the Rust file are skipped: no JSON codec layer (`json_ops.rs`) is ported
## yet, and this crate's `dynamic_ops.rs`/`codec/*` (the generic
## DataFixerUpper-style Codec/DynamicOps framework this crate exists to
## support) rely on Rust trait objects and generic associated types Nimony
## doesn't have an equivalent for - porting `Number` and `Lifecycle` here
## covers the two pieces of this crate with no such dependency; the rest is
## deferred until a concrete need (e.g. NBT-backed dynamic ops) forces a
## design for it.

type
  NumberKind* = enum
    nkByte
    nkShort
    nkInt
    nkLong
    nkFloat
    nkDouble

  Number* = object
    case kind*: NumberKind
    of nkByte: byteVal*: int8
    of nkShort: shortVal*: int16
    of nkInt: intVal*: int32
    of nkLong: longVal*: int64
    of nkFloat: floatVal*: float32
    of nkDouble: doubleVal*: float64

proc toInt64*(n: Number): int64 =
  case n.kind
  of nkByte: int64(n.byteVal)
  of nkShort: int64(n.shortVal)
  of nkInt: int64(n.intVal)
  of nkLong: n.longVal
  of nkFloat: int64(n.floatVal)
  of nkDouble: int64(n.doubleVal)

proc toInt32*(n: Number): int32 =
  case n.kind
  of nkByte: int32(n.byteVal)
  of nkShort: int32(n.shortVal)
  of nkInt: n.intVal
  of nkLong: int32(n.longVal)
  of nkFloat: int32(n.floatVal)
  of nkDouble: int32(n.doubleVal)

proc toInt16*(n: Number): int16 =
  ## Upstream converts via `i32` first (matching Java's cast chain), then to
  ## the target width.
  int16(toInt32(n))

proc toInt8*(n: Number): int8 =
  int8(toInt32(n))

proc toUInt8*(n: Number): uint8 =
  cast[uint8](toInt8(n))

proc toFloat32*(n: Number): float32 =
  case n.kind
  of nkByte: float32(n.byteVal)
  of nkShort: float32(n.shortVal)
  of nkInt: float32(n.intVal)
  of nkLong: float32(n.longVal)
  of nkFloat: n.floatVal
  of nkDouble: float32(n.doubleVal)

proc toFloat64*(n: Number): float64 =
  case n.kind
  of nkByte: float64(n.byteVal)
  of nkShort: float64(n.shortVal)
  of nkInt: float64(n.intVal)
  of nkLong: float64(n.longVal)
  of nkFloat: float64(n.floatVal)
  of nkDouble: n.doubleVal

proc `$`*(n: Number): string =
  case n.kind
  of nkByte: $n.byteVal
  of nkShort: $n.shortVal
  of nkInt: $n.intVal
  of nkLong: $n.longVal
  of nkFloat: $n.floatVal
  of nkDouble: $n.doubleVal
