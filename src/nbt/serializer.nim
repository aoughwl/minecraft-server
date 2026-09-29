## Low-level NBT serialization support.
## Port of pumpkingmc/crates/pumpkin-nbt/src/serializer.rs
##
## Rust models this as a `NbtWriteHelper` trait with two implementations
## (Java big-endian/CESU-8, Bedrock little-endian/varint). Nimony has no
## trait objects worth reaching for here, so both writers share one object
## type with a `mode` discriminant and every proc branches on it - the same
## shape `define_write_number_be!`/`_le!` generate on the Rust side.

import nbtbase

type
  NbtWriteMode* = enum
    nwmJava    ## Big-endian numbers, length-prefixed CESU-8 strings (u16 len).
    nwmBedrock ## Little-endian fixed numbers, LEB128 varint i32/i64, u32-len UTF-8 strings.

  NbtWriter* = object
    mode*: NbtWriteMode
    buf*: seq[byte]

proc newNbtWriter*(mode: NbtWriteMode): NbtWriter =
  NbtWriter(mode: mode, buf: @[])

proc writeSlice*(w: var NbtWriter, value: openArray[byte]) =
  for b in value:
    w.buf.add(b)

proc writeU8*(w: var NbtWriter, value: uint8) =
  w.buf.add(value)

proc writeI8*(w: var NbtWriter, value: int8) =
  w.buf.add(cast[uint8](value))

proc writeBE16(w: var NbtWriter, value: uint16) =
  w.buf.add(uint8(value shr 8))
  w.buf.add(uint8(value and 0xFF))

proc writeBE32(w: var NbtWriter, value: uint32) =
  w.buf.add(uint8(value shr 24))
  w.buf.add(uint8((value shr 16) and 0xFF))
  w.buf.add(uint8((value shr 8) and 0xFF))
  w.buf.add(uint8(value and 0xFF))

proc writeBE64(w: var NbtWriter, value: uint64) =
  var shift = 56
  while shift >= 0:
    w.buf.add(uint8((value shr uint64(shift)) and 0xFF'u64))
    shift -= 8

proc writeLE16(w: var NbtWriter, value: uint16) =
  w.buf.add(uint8(value and 0xFF))
  w.buf.add(uint8(value shr 8))

proc writeLE32(w: var NbtWriter, value: uint32) =
  w.buf.add(uint8(value and 0xFF))
  w.buf.add(uint8((value shr 8) and 0xFF))
  w.buf.add(uint8((value shr 16) and 0xFF))
  w.buf.add(uint8(value shr 24))

proc writeLE64(w: var NbtWriter, value: uint64) =
  var shift = 0
  while shift <= 56:
    w.buf.add(uint8((value shr uint64(shift)) and 0xFF'u64))
    shift += 8

proc writeVarU32(w: var NbtWriter, value: uint32) =
  ## LEB128.
  var v = value
  while true:
    var byteVal = uint8(v and 0x7F'u32)
    v = v shr 7
    if v != 0:
      byteVal = byteVal or 0x80'u8
    w.writeU8(byteVal)
    if v == 0:
      break

proc writeVarI32(w: var NbtWriter, value: int32) =
  ## ZigZag.
  let zz = (uint32(value) shl 1) xor uint32(value shr 31)
  w.writeVarU32(zz)

proc writeVarU64(w: var NbtWriter, value: uint64) =
  var v = value
  while true:
    var byteVal = uint8(v and 0x7F'u64)
    v = v shr 7
    if v != 0:
      byteVal = byteVal or 0x80'u8
    w.writeU8(byteVal)
    if v == 0:
      break

proc writeVarI64(w: var NbtWriter, value: int64) =
  let zz = (uint64(value) shl 1) xor uint64(value shr 63)
  w.writeVarU64(zz)

proc writeI16*(w: var NbtWriter, value: int16) =
  case w.mode
  of nwmJava: w.writeBE16(cast[uint16](value))
  of nwmBedrock: w.writeLE16(cast[uint16](value))

proc writeI32*(w: var NbtWriter, value: int32) =
  case w.mode
  of nwmJava: w.writeBE32(cast[uint32](value))
  of nwmBedrock: w.writeVarI32(value)

proc writeI64*(w: var NbtWriter, value: int64) =
  case w.mode
  of nwmJava: w.writeBE64(cast[uint64](value))
  of nwmBedrock: w.writeVarI64(value)

proc writeF32*(w: var NbtWriter, value: float32) =
  let bits = cast[uint32](value)
  case w.mode
  of nwmJava: w.writeBE32(bits)
  of nwmBedrock: w.writeLE32(bits)

proc writeF64*(w: var NbtWriter, value: float64) =
  let bits = cast[uint64](value)
  case w.mode
  of nwmJava: w.writeBE64(bits)
  of nwmBedrock: w.writeLE64(bits)

proc toJavaCesu8(value: string): seq[byte] =
  ## CESU-8: like UTF-8, but code points above U+FFFF are encoded as a
  ## surrogate pair, each half emitted as its own 3-byte UTF-8 sequence,
  ## rather than one 4-byte UTF-8 sequence. Also re-encodes NUL as the
  ## non-standard 2-byte form `C0 80`, matching Java's modified UTF-8.
  result = @[]
  var i = 0
  let n = value.len
  while i < n:
    let c0 = value[i].uint8
    if c0 == 0:
      result.add(0xC0'u8); result.add(0x80'u8)
      inc i
    elif c0 < 0x80:
      result.add(c0)
      inc i
    elif (c0 and 0xE0'u8) == 0xC0'u8 and i + 1 < n:
      result.add(c0); result.add(value[i+1].uint8)
      i += 2
    elif (c0 and 0xF0'u8) == 0xE0'u8 and i + 2 < n:
      result.add(c0); result.add(value[i+1].uint8); result.add(value[i+2].uint8)
      i += 3
    elif (c0 and 0xF8'u8) == 0xF0'u8 and i + 3 < n:
      # 4-byte UTF-8 sequence: decode the code point, then re-emit as a
      # CESU-8 surrogate pair (two 3-byte sequences).
      let c1 = value[i+1].uint8
      let c2 = value[i+2].uint8
      let c3 = value[i+3].uint8
      let cp = (uint32(c0 and 0x07'u8) shl 18) or
               (uint32(c1 and 0x3F'u8) shl 12) or
               (uint32(c2 and 0x3F'u8) shl 6) or
               uint32(c3 and 0x3F'u8)
      let v = cp - 0x10000'u32
      let hi = 0xD800'u32 + (v shr 10)
      let lo = 0xDC00'u32 + (v and 0x3FF'u32)
      for surrogate in [hi, lo]:
        result.add(uint8(0xE0'u8 or uint8(surrogate shr 12)))
        result.add(uint8(0x80'u8 or uint8((surrogate shr 6) and 0x3F'u32)))
        result.add(uint8(0x80'u8 or uint8(surrogate and 0x3F'u32)))
      i += 4
    else:
      # Malformed leading byte; pass it through rather than lose data.
      result.add(c0)
      inc i

proc writeString*(w: var NbtWriter, value: string): NbtVoidResult =
  case w.mode
  of nwmJava:
    let encoded = toJavaCesu8(value)
    if encoded.len > 0xFFFF:
      return errVoid(largeLength(encoded.len))
    w.writeBE16(uint16(encoded.len))
    w.writeSlice(encoded)
  of nwmBedrock:
    let n = value.len
    if n > int(uint32.high):
      return errVoid(largeLength(n))
    w.writeVarU32(uint32(n))
    for ch in value:
      w.writeU8(ch.uint8)
  okVoid()
