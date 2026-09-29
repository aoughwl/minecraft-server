## Shared constants and error type for the NBT crate.
## Port of pumpkingmc/crates/pumpkin-nbt/src/lib.rs
##
## Rust returns `Result<T, Error>` with a rich `Error` enum. Nimony has no
## Nim-compatible exceptions (see `~/nimony/doc/differences.md`): its
## `{.raises.}`/`raise` mechanism is built on a fixed, non-extensible
## `ErrorCode` enum that can't carry a per-error tag id or length like
## `Error::UnknownTagId(u8)` does. So every fallible NBT proc here returns an
## explicit `NbtResult[T]` instead of raising - the caller checks `isOk`
## the way Rust code here checks `Result::is_ok`/uses `?`.

const
  EndId* = 0x00'u8
  ByteId* = 0x01'u8
  ShortId* = 0x02'u8
  IntId* = 0x03'u8
  LongId* = 0x04'u8
  FloatId* = 0x05'u8
  DoubleId* = 0x06'u8
  ByteArrayId* = 0x07'u8
  StringId* = 0x08'u8
  ListId* = 0x09'u8
  CompoundId* = 0x0A'u8
  IntArrayId* = 0x0B'u8
  LongArrayId* = 0x0C'u8

  MaxArrayLength* = 512_000
  MaxNbtDepth* = 512

type
  NbtErrorKind* = enum
    nekNoRootCompound
    nekUnknownTagId
    nekCesu8Decoding
    nekUtf8Decoding
    nekUnsupportedType
    nekIncomplete
    nekNegativeLength
    nekLargeLength
    nekVarIntTooLarge
    nekVarLongTooLarge
    nekMaxDepthExceeded
    nekInvalidListTag

  NbtError* = object
    kind*: NbtErrorKind
    msg*: string

  NbtResult*[T] = object
    case isOk*: bool
    of true:
      value*: T
    of false:
      error*: NbtError

proc ok*[T](value: sink T): NbtResult[T] =
  NbtResult[T](isOk: true, value: value)

proc errRes*[T](e: NbtError): NbtResult[T] =
  NbtResult[T](isOk: false, error: e)

type
  NbtVoidResult* = object
    ## `NbtResult[void]` isn't representable (a `void`-typed object field
    ## isn't legal), so procs whose Rust signature is `Result<()>` return
    ## this instead.
    isOk*: bool
    error*: NbtError

proc okVoid*(): NbtVoidResult =
  NbtVoidResult(isOk: true)

proc errVoid*(e: NbtError): NbtVoidResult =
  NbtVoidResult(isOk: false, error: e)

proc nbtError(kind: NbtErrorKind, msg: string): NbtError =
  NbtError(kind: kind, msg: msg)

proc noRootCompound*(id: uint8): NbtError =
  nbtError(nekNoRootCompound, "The root tag of the NBT file is not a compound tag. Received tag id: " & $id)

proc unknownTagId*(id: uint8): NbtError =
  nbtError(nekUnknownTagId, "Encountered an unknown NBT tag id: " & $id & ".")

proc negativeLength*(len: int32): NbtError =
  nbtError(nekNegativeLength, "Negative list length: " & $len)

proc largeLength*(len: int): NbtError =
  nbtError(nekLargeLength, "Length too large: " & $len)

proc maxDepthExceeded*(): NbtError =
  nbtError(nekMaxDepthExceeded, "NBT depth exceeded maximum allowed limit")

proc invalidListTag*(id: uint8): NbtError =
  nbtError(nekInvalidListTag, "Invalid element tag type for list: " & $id)

proc varIntTooLarge*(): NbtError =
  nbtError(nekVarIntTooLarge, "Failed to decode varint - value too large")

proc varLongTooLarge*(): NbtError =
  nbtError(nekVarLongTooLarge, "Failed to decode varlong - value too large")

proc utf8Decoding*(): NbtError =
  nbtError(nekUtf8Decoding, "Failed to UTF-8 Decode")

proc incomplete*(msg: string): NbtError =
  nbtError(nekIncomplete, "NBT reading was cut short: " & msg)
