## The concrete network read/write primitives packet types build on.
## Port of upstream/protocol/src/ser/mod.rs's `NetworkReadExt`/
## `NetworkWriteExt` traits.
##
## Upstream is a trait implemented generically for any `Read`/`Write`.
## Nimony has no traits, so (matching src/nbt/serializer.nim's/
## deserializer.nim's precedent) this is one concrete `NetReader`/
## `NetWriter` pair operating on an owned `seq[byte]` with a cursor/buffer,
## rather than a generic stream abstraction.
##
## NOT ported here (left as TODOs for whoever reaches them): `get_uuid`'s
## caller-facing `uuid::Uuid` type (we return the raw hi/lo `u64` pair
## instead - no Uuid type exists anywhere in this port yet), NBT-with-
## version and `TextComponent`/`BlockPos`-dependent methods (those upstream
## types aren't ported), and the legacy pre-1.8 gzip'd-NBT read path.

import protobase, varint

type
  NetReader* = object
    data*: seq[byte]
    pos*: int

  NetWriter* = object
    buf*: seq[byte]

proc newNetReader*(data: sink seq[byte]): NetReader =
  NetReader(data: data, pos: 0)

proc newNetWriter*(): NetWriter =
  NetWriter(buf: @[])

proc remaining(r: NetReader): int {.inline.} =
  r.data.len - r.pos

# --- reads -------------------------------------------------------------

proc readBytesToBuf*(r: var NetReader, buf: var seq[byte]): ProtoReadVoidResult =
  let n = buf.len
  if remaining(r) < n:
    return readErrVoid(incompleteRead("needed " & $n & " bytes, only " & $remaining(r) & " remaining"))
  for i in 0 ..< n:
    buf[i] = r.data[r.pos + i]
  r.pos += n
  readOkVoid()

proc getU8*(r: var NetReader): ProtoReadResult[uint8] =
  if remaining(r) < 1:
    return readErr[uint8](cleanEof("u8"))
  result = readOk[uint8](r.data[r.pos])
  inc r.pos

proc getI8*(r: var NetReader): ProtoReadResult[int8] =
  let b = getU8(r)
  if not b.isOk: return readErr[int8](b.error)
  readOk[int8](cast[int8](b.value))

proc getSlice(r: var NetReader, n: int): ProtoReadResult[seq[byte]] =
  if remaining(r) < n:
    return readErr[seq[byte]](cleanEof($n & " bytes"))
  var s = newSeq[byte](n)
  for i in 0 ..< n: s[i] = r.data[r.pos + i]
  r.pos += n
  readOk[seq[byte]](s)

proc beU16(b: seq[byte]): uint16 {.inline.} = (uint16(b[0]) shl 8) or uint16(b[1])
proc beU32(b: seq[byte]): uint32 {.inline.} =
  (uint32(b[0]) shl 24) or (uint32(b[1]) shl 16) or (uint32(b[2]) shl 8) or uint32(b[3])
proc beU64(b: seq[byte]): uint64 {.inline.} =
  result = 0
  for x in b: result = (result shl 8) or uint64(x)

proc getI16Be*(r: var NetReader): ProtoReadResult[int16] =
  let s = getSlice(r, 2)
  if not s.isOk: return readErr[int16](s.error)
  readOk[int16](cast[int16](beU16(s.value)))

proc getU16Be*(r: var NetReader): ProtoReadResult[uint16] =
  let s = getSlice(r, 2)
  if not s.isOk: return readErr[uint16](s.error)
  readOk[uint16](beU16(s.value))

proc getI32Be*(r: var NetReader): ProtoReadResult[int32] =
  let s = getSlice(r, 4)
  if not s.isOk: return readErr[int32](s.error)
  readOk[int32](cast[int32](beU32(s.value)))

proc getU32Be*(r: var NetReader): ProtoReadResult[uint32] =
  let s = getSlice(r, 4)
  if not s.isOk: return readErr[uint32](s.error)
  readOk[uint32](beU32(s.value))

proc getI64Be*(r: var NetReader): ProtoReadResult[int64] =
  let s = getSlice(r, 8)
  if not s.isOk: return readErr[int64](s.error)
  readOk[int64](cast[int64](beU64(s.value)))

proc getU64Be*(r: var NetReader): ProtoReadResult[uint64] =
  let s = getSlice(r, 8)
  if not s.isOk: return readErr[uint64](s.error)
  readOk[uint64](beU64(s.value))

proc getF32Be*(r: var NetReader): ProtoReadResult[float32] =
  let s = getSlice(r, 4)
  if not s.isOk: return readErr[float32](s.error)
  readOk[float32](cast[float32](beU32(s.value)))

proc getF64Be*(r: var NetReader): ProtoReadResult[float64] =
  let s = getSlice(r, 8)
  if not s.isOk: return readErr[float64](s.error)
  readOk[float64](cast[float64](beU64(s.value)))

proc getBool*(r: var NetReader): ProtoReadResult[bool] =
  let b = getU8(r)
  if not b.isOk: return readErr[bool](b.error)
  readOk[bool](b.value != 0)

proc getVarInt*(r: var NetReader): ProtoReadResult[VarInt] =
  decodeJava(r.data, r.pos)

proc getVarUInt*(r: var NetReader): ProtoReadResult[VarUInt] =
  decode(r.data, r.pos, VarUInt)

proc getVarLong*(r: var NetReader): ProtoReadResult[VarLong] =
  decodeJava(r.data, r.pos, VarLong)

proc getVarULong*(r: var NetReader): ProtoReadResult[VarULong] =
  decode(r.data, r.pos, VarULong)

proc utf16Len(s: string): int =
  ## Number of UTF-16 code units `s` would encode as, decoding `s` as UTF-8.
  ## Used only for the bound check in `getStrBounded` (matching upstream's
  ## `string.encode_utf16().nth(bound)`), not for producing UTF-16 data.
  var i = 0
  result = 0
  let n = s.len
  while i < n:
    let c0 = s[i].uint8
    var cp: uint32
    var step: int
    if c0 < 0x80: cp = uint32(c0); step = 1
    elif (c0 and 0xE0'u8) == 0xC0'u8 and i + 1 < n:
      cp = (uint32(c0 and 0x1F'u8) shl 6) or uint32(s[i+1].uint8 and 0x3F'u8); step = 2
    elif (c0 and 0xF0'u8) == 0xE0'u8 and i + 2 < n:
      cp = (uint32(c0 and 0x0F'u8) shl 12) or (uint32(s[i+1].uint8 and 0x3F'u8) shl 6) or
           uint32(s[i+2].uint8 and 0x3F'u8); step = 3
    elif (c0 and 0xF8'u8) == 0xF0'u8 and i + 3 < n:
      cp = (uint32(c0 and 0x07'u8) shl 18) or (uint32(s[i+1].uint8 and 0x3F'u8) shl 12) or
           (uint32(s[i+2].uint8 and 0x3F'u8) shl 6) or uint32(s[i+3].uint8 and 0x3F'u8); step = 4
    else: cp = uint32(c0); step = 1
    inc(result, if cp > 0xFFFF'u32: 2 else: 1)
    i += step

proc getStrBounded*(r: var NetReader, bound: int): ProtoReadResult[string] =
  let lenR = getVarUInt(r)
  if not lenR.isOk: return readErr[string](lenR.error)
  let bytesLen = int(lenR.value.value)
  const maxPacketDataSize = 8_388_608
  let maxUtf8Bytes = min(bound * 3, maxPacketDataSize)
  if bytesLen > maxUtf8Bytes:
    return readErr[string](tooLarge("string has too many bytes (" & $bytesLen & " > " & $maxUtf8Bytes & ")"))
  let s = getSlice(r, bytesLen)
  if not s.isOk: return readErr[string](s.error)
  var str = newString(bytesLen)
  for i, b in s.value: str[i] = char(b)
  if utf16Len(str) > bound:
    return readErr[string](tooLarge("string has too many UTF-16 characters (more than the maximum limit " & $bound & ")"))
  readOk[string](str)

proc getStr*(r: var NetReader): ProtoReadResult[string] =
  getStrBounded(r, 32767)

proc getUuidPair*(r: var NetReader): ProtoReadResult[(uint64, uint64)] =
  ## Returns the (high, low) 64-bit halves upstream's `uuid::Uuid::from_bytes`
  ## would hold - no `Uuid` type exists in this port yet.
  let hi = getU64Be(r)
  if not hi.isOk: return readErr[(uint64, uint64)](hi.error)
  let lo = getU64Be(r)
  if not lo.isOk: return readErr[(uint64, uint64)](lo.error)
  readOk[(uint64, uint64)]((hi.value, lo.value))

proc getFixedBitset*(r: var NetReader, bits: int): ProtoReadResult[seq[byte]] =
  let byteCount = (bits + 7) div 8
  getSlice(r, byteCount)

type
  OptionResult*[G] = object
    isOk*: bool
    error*: ReadingError
    present*: bool
    value*: G

proc getOption*[G](r: var NetReader, parse: proc(r: var NetReader): ProtoReadResult[G] {.closure.}): OptionResult[G] =
  ## Nimony's object-constructor syntax with omitted fields implicitly
  ## `default()`-inits them, which isn't legal for an unconstrained generic
  ## field (`default(G)` has no match) - so every branch here builds the
  ## result via a `var` + field assignment instead of a literal
  ## constructor, to avoid touching `value` except on the success path.
  let hasR = getBool(r)
  if not hasR.isOk:
    var res: OptionResult[G]
    res.isOk = false
    res.error = hasR.error
    return res
  if hasR.value:
    let v = parse(r)
    if not v.isOk:
      var res: OptionResult[G]
      res.isOk = false
      res.error = v.error
      return res
    var res: OptionResult[G]
    res.isOk = true
    res.present = true
    res.value = v.value
    res
  else:
    var res: OptionResult[G]
    res.isOk = true
    res.present = false
    res

type
  ListResult*[G] = object
    isOk*: bool
    error*: ReadingError
    items*: seq[G]

proc getList*[G](r: var NetReader, parse: proc(r: var NetReader): ProtoReadResult[G] {.closure.}): ListResult[G] =
  const maxListSize = 65536
  let lenR = getVarInt(r)
  if not lenR.isOk:
    return ListResult[G](isOk: false, error: lenR.error)
  let len = int(lenR.value.value)
  if len > maxListSize:
    return ListResult[G](isOk: false, error: tooLarge("List length " & $len & " exceeds limit"))
  var list: seq[G] = @[]
  for i in 0 ..< len:
    let v = parse(r)
    if not v.isOk:
      return ListResult[G](isOk: false, error: v.error)
    list.add(v.value)
  ListResult[G](isOk: true, items: list)

# --- writes --------------------------------------------------------------

proc writeSlice*(w: var NetWriter, data: openArray[byte]) =
  for b in data: w.buf.add(b)

proc writeU8*(w: var NetWriter, v: uint8) = w.buf.add(v)
proc writeI8*(w: var NetWriter, v: int8) = w.buf.add(cast[uint8](v))

proc writeBE16(w: var NetWriter, v: uint16) =
  w.buf.add(uint8(v shr 8)); w.buf.add(uint8(v and 0xFF))
proc writeBE32(w: var NetWriter, v: uint32) =
  w.buf.add(uint8(v shr 24)); w.buf.add(uint8((v shr 16) and 0xFF))
  w.buf.add(uint8((v shr 8) and 0xFF)); w.buf.add(uint8(v and 0xFF))
proc writeBE64(w: var NetWriter, v: uint64) =
  var shift = 56
  while shift >= 0:
    w.buf.add(uint8((v shr uint64(shift)) and 0xFF'u64))
    shift -= 8

proc writeI16Be*(w: var NetWriter, v: int16) = writeBE16(w, cast[uint16](v))
proc writeU16Be*(w: var NetWriter, v: uint16) = writeBE16(w, v)
proc writeI32Be*(w: var NetWriter, v: int32) = writeBE32(w, cast[uint32](v))
proc writeU32Be*(w: var NetWriter, v: uint32) = writeBE32(w, v)
proc writeI64Be*(w: var NetWriter, v: int64) = writeBE64(w, cast[uint64](v))
proc writeU64Be*(w: var NetWriter, v: uint64) = writeBE64(w, v)
proc writeF32Be*(w: var NetWriter, v: float32) = writeBE32(w, cast[uint32](v))
proc writeF64Be*(w: var NetWriter, v: float64) = writeBE64(w, cast[uint64](v))

proc writeBool*(w: var NetWriter, v: bool) =
  writeU8(w, if v: 1'u8 else: 0'u8)

proc writeVarInt*(w: var NetWriter, v: VarInt) =
  encodeJava(v, w.buf)

proc writeVarUInt*(w: var NetWriter, v: VarUInt) =
  encode(v, w.buf)

proc writeVarLong*(w: var NetWriter, v: VarLong) =
  encodeJava(v, w.buf)

proc writeStringBounded*(w: var NetWriter, s: string, bound: int): ProtoWriteVoidResult =
  if utf16Len(s) > bound:
    return writeErrVoid(WritingError(kind: weMessage,
      msg: "string has too many UTF-16 characters (more than the maximum limit " & $bound & ")"))
  writeVarUInt(w, newVarUInt(uint32(s.len)))
  for ch in s: writeU8(w, ch.uint8)
  writeOkVoid()

proc writeString*(w: var NetWriter, s: string): ProtoWriteVoidResult =
  writeStringBounded(w, s, 32767)

proc writeUuidPair*(w: var NetWriter, hi, lo: uint64) =
  writeU64Be(w, hi)
  writeU64Be(w, lo)

proc writeFixedBitset*(w: var NetWriter, bits: int, bitSet: seq[byte]) =
  writeSlice(w, bitSet)
