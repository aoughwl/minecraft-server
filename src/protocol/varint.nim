## Variable-length integer codecs used by the Minecraft network protocol.
## Port of pumpkingmc/crates/pumpkin-protocol/src/codec/var_int.rs and
## var_uint.rs.
##
## Two distinct wire shapes coexist here, matching upstream exactly (and
## matching the same Java-vs-Bedrock split already established in
## src/nbt/serializer.nim / deserializer.nim):
## - `VarInt.encode`/`.decode` (Java Edition): plain LEB128 of the value's
##   `u32` bit pattern, no ZigZag. This is the one actually used on the
##   Java wire for packet-length prefixes and most integer fields.
## - `VarInt`'s `PacketWrite`/`PacketRead` impl (Bedrock): LEB128 of the
##   ZigZag-encoded value. Upstream's own test names this
##   `bedrock_zig_zag_round_trip`.
## `VarUInt` only has the plain-LEB128 shape (no signed/ZigZag variant).
##
## Reader/writer here are the same "operate on an owned seq[byte] with a
## position cursor" shape as src/nbt/deserializer.nim's `NbtReader`, rather
## than reproducing Rust's generic `Read`/`Write`/`AsyncRead` split - the
## async variants (`decode_async`/`encode_async`) are tokio-runtime
## plumbing with no Nimony equivalent yet and are not ported.

import protobase

const MaxVarIntSize* = 5
const MaxVarLongSize* = 10

type
  VarInt* = object
    value*: int32

  VarUInt* = object
    value*: uint32

  VarLong* = object
    value*: int64

  VarULong* = object
    value*: uint64

proc newVarInt*(value: int32): VarInt {.inline.} = VarInt(value: value)
proc newVarUInt*(value: uint32): VarUInt {.inline.} = VarUInt(value: value)
proc newVarLong*(value: int64): VarLong {.inline.} = VarLong(value: value)
proc newVarULong*(value: uint64): VarULong {.inline.} = VarULong(value: value)

proc leadingZeros32(n: uint32): int =
  if n == 0:
    return 32
  var m = n
  result = 0
  var mask = 0x80000000'u32
  while (m and mask) == 0:
    inc result
    mask = mask shr 1

proc writtenSizeVarInt*(v: VarInt): int =
  let n = cast[uint32](v.value)
  if n == 0: 1
  else: (31 - leadingZeros32(n)) div 7 + 1

proc writtenSizeVarUInt*(v: VarUInt): int =
  if v.value == 0: 1
  else: (31 - leadingZeros32(v.value)) div 7 + 1

# --- Java: plain LEB128 (VarInt.encode/decode) ------------------------------

proc encodeJava*(v: VarInt, buf: var seq[byte]) =
  var val = cast[uint32](v.value)
  while val > 0x7F'u32:
    buf.add(uint8(val) or 0x80'u8)
    val = val shr 7
  buf.add(uint8(val))

proc decodeJava*(data: seq[byte], pos: var int): ProtoReadResult[VarInt] =
  var val: int32 = 0
  var i = 0
  while i < MaxVarIntSize:
    if pos >= data.len:
      return readErr[VarInt](cleanEof("VarInt"))
    let b = data[pos]
    inc pos
    if i == MaxVarIntSize - 1 and (b and 0x70'u8) != 0:
      return readErr[VarInt](tooLarge("VarInt"))
    val = val or ((int32(b) and 0x7F'i32) shl (i * 7))
    if (b and 0x80'u8) == 0:
      return readOk[VarInt](VarInt(value: val))
    inc i
  readErr[VarInt](tooLarge("VarInt"))

# --- Bedrock: ZigZag LEB128 (VarInt's PacketWrite/PacketRead impl) ---------

proc encodeBedrock*(v: VarInt, buf: var seq[byte]) =
  var val = (cast[uint32](v.value) shl 1) xor cast[uint32](v.value shr 31)
  while val > 0x7F'u32:
    buf.add(uint8(val and 0x7F'u32) or 0x80'u8)
    val = val shr 7
  buf.add(uint8(val))

proc decodeBedrock*(data: seq[byte], pos: var int): ProtoReadResult[VarInt] =
  var val: uint32 = 0
  var i = 0
  while i < MaxVarIntSize:
    if pos >= data.len:
      return readErr[VarInt](cleanEof("VarInt"))
    let b = data[pos]
    inc pos
    if i == MaxVarIntSize - 1 and (b and 0x70'u8) != 0:
      return readErr[VarInt](tooLarge("VarInt"))
    val = val or ((uint32(b) and 0x7F'u32) shl (i * 7))
    if (b and 0x80'u8) == 0:
      let signed = cast[int32]((val shr 1)) xor (-cast[int32](val and 1'u32))
      return readOk[VarInt](VarInt(value: signed))
    inc i
  readErr[VarInt](tooLarge("VarInt"))

# --- VarUInt: plain LEB128 only ---------------------------------------------

proc encode*(v: VarUInt, buf: var seq[byte]) =
  var val = v.value
  while true:
    var b = uint8(val and 0x7F'u32)
    val = val shr 7
    if val != 0:
      b = b or 0x80'u8
    buf.add(b)
    if val == 0:
      break

proc decode*(data: seq[byte], pos: var int, _: typedesc[VarUInt]): ProtoReadResult[VarUInt] =
  var val: uint32 = 0
  var i = 0
  while i < MaxVarIntSize:
    if pos >= data.len:
      return readErr[VarUInt](cleanEof("VarUInt"))
    let b = data[pos]
    inc pos
    if i == MaxVarIntSize - 1 and (b and 0x70'u8) != 0:
      return readErr[VarUInt](tooLarge("VarUInt"))
    val = val or ((uint32(b) and 0x7F'u32) shl (i * 7))
    if (b and 0x80'u8) == 0:
      return readOk[VarUInt](VarUInt(value: val))
    inc i
  readErr[VarUInt](tooLarge("VarUInt"))

# --- VarLong: same two shapes as VarInt, 64-bit, up to 10 bytes ------------

proc encodeJava*(v: VarLong, buf: var seq[byte]) =
  var val = cast[uint64](v.value)
  while val > 0x7F'u64:
    buf.add(uint8(val) or 0x80'u8)
    val = val shr 7
  buf.add(uint8(val))

proc decodeJava*(data: seq[byte], pos: var int, _: typedesc[VarLong]): ProtoReadResult[VarLong] =
  var val: int64 = 0
  var i = 0
  while i < MaxVarLongSize:
    if pos >= data.len:
      return readErr[VarLong](cleanEof("VarLong"))
    let b = data[pos]
    inc pos
    val = val or ((int64(b) and 0x7F'i64) shl (i * 7))
    if (b and 0x80'u8) == 0:
      return readOk[VarLong](VarLong(value: val))
    inc i
  readErr[VarLong](tooLarge("VarLong"))

proc encode*(v: VarULong, buf: var seq[byte]) =
  var val = v.value
  while true:
    var b = uint8(val and 0x7F'u64)
    val = val shr 7
    if val != 0:
      b = b or 0x80'u8
    buf.add(b)
    if val == 0:
      break

proc decode*(data: seq[byte], pos: var int, _: typedesc[VarULong]): ProtoReadResult[VarULong] =
  var val: uint64 = 0
  var i = 0
  while i < MaxVarLongSize:
    if pos >= data.len:
      return readErr[VarULong](cleanEof("VarULong"))
    let b = data[pos]
    inc pos
    val = val or ((uint64(b) and 0x7F'u64) shl (i * 7))
    if (b and 0x80'u8) == 0:
      return readOk[VarULong](VarULong(value: val))
    inc i
  readErr[VarULong](tooLarge("VarULong"))
