## Port of upstream/util/src/y_offset.rs
##
## Rust's `YOffset` is `#[serde(untagged)]` over three struct variants;
## modeled here as a plain case-object variant (deserialization itself is
## not ported yet - see identifier.nim's note on serde).

type
  YOffsetKind* = enum
    yokAbsolute
    yokAboveBottom
    yokBelowTop

  YOffset* = object
    case kind*: YOffsetKind
    of yokAbsolute:
      absolute*: int16
    of yokAboveBottom:
      aboveBottom*: int8
    of yokBelowTop:
      belowTop*: int8

proc getY*(o: YOffset, minY: int16, height: uint16): int32 =
  case o.kind
  of yokAboveBottom:
    int32(minY) + int32(o.aboveBottom)
  of yokBelowTop:
    int32(height) - 1'i32 + int32(minY) - int32(o.belowTop)
  of yokAbsolute:
    int32(o.absolute)
