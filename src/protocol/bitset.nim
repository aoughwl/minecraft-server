## A packed bit set used by several Java Edition packets.
## Port of upstream/protocol/src/codec/bit_set.rs
##
## Upstream's `encode_with_version`/`decode_with_version` branch on a
## Minecraft version (pre/post 26.3: long-array vs. trimmed little-endian
## byte-array wire shape). `pumpkin_util::version::JavaMinecraftVersion`
## isn't ported yet, so the version check is a plain `bool` parameter here
## (`v26_3OrLater`) instead - same value, no version type dependency.

import netcodec, protobase, varint

const MaxLength = 1024

type
  BitSet* = object
    words*: seq[int64]

proc newBitSet*(): BitSet = BitSet(words: @[])
proc fromU64*(val: uint64): BitSet = BitSet(words: @[cast[int64](val)])
proc fromI64*(val: int64): BitSet = BitSet(words: @[val])
proc fromLongs*(longs: sink seq[int64]): BitSet = BitSet(words: longs)

proc asU64*(b: BitSet): uint64 =
  if b.words.len == 0: 0'u64 else: cast[uint64](b.words[0])

proc asI64*(b: BitSet): int64 =
  if b.words.len == 0: 0'i64 else: b.words[0]

proc getBit*(b: BitSet, index: int): bool =
  let wordIdx = index div 64
  let bitIdx = index mod 64
  if wordIdx >= b.words.len: return false
  (b.words[wordIdx] and (1'i64 shl bitIdx)) != 0

proc setBit*(b: var BitSet, index: int, val: bool) =
  let wordIdx = index div 64
  let bitIdx = index mod 64
  if wordIdx >= b.words.len:
    let oldLen = b.words.len
    b.words.setLen(wordIdx + 1)
    for i in oldLen ..< b.words.len: b.words[i] = 0
  if val:
    b.words[wordIdx] = b.words[wordIdx] or (1'i64 shl bitIdx)
  else:
    b.words[wordIdx] = b.words[wordIdx] and not (1'i64 shl bitIdx)

proc countOnes*(b: BitSet): int =
  result = 0
  for w in b.words:
    var u = cast[uint64](w)
    while u != 0:
      inc result
      u = u and (u - 1)

proc checkedLen(length: int32): ProtoReadResult[int] =
  if length < 0 or length > MaxLength:
    return readErr[int](tooLarge("BitSet"))
  readOk[int](int(length))

proc encode*(b: BitSet, w: var NetWriter): ProtoWriteVoidResult =
  if b.words.len > int(int32.high):
    return writeErrVoid(WritingError(kind: weMessage, msg: $b.words.len & " isn't representable as a VarInt"))
  writeVarInt(w, newVarInt(int32(b.words.len)))
  for word in b.words:
    writeI64Be(w, word)
  writeOkVoid()

proc decode*(r: var NetReader): ProtoReadResult[BitSet] =
  let lenR = getVarInt(r)
  if not lenR.isOk: return readErr[BitSet](lenR.error)
  let lenChk = checkedLen(lenR.value.value)
  if not lenChk.isOk: return readErr[BitSet](lenChk.error)
  var arr = newSeq[int64](lenChk.value)
  for i in 0 ..< arr.len:
    let v = getI64Be(r)
    if not v.isOk: return readErr[BitSet](v.error)
    arr[i] = v.value
  readOk[BitSet](BitSet(words: arr))

proc encodeWithVersion*(b: BitSet, w: var NetWriter, v26_3OrLater: bool): ProtoWriteVoidResult =
  ## Since 26.3, bit sets are sent as a little-endian byte array without
  ## trailing zero bytes, instead of a long array.
  if not v26_3OrLater:
    return encode(b, w)
  var bytes: seq[byte] = @[]
  for word in b.words:
    let u = cast[uint64](word)
    var shift = 0
    while shift <= 56:
      bytes.add(uint8((u shr uint64(shift)) and 0xFF'u64))
      shift += 8
  while bytes.len > 0 and bytes[^1] == 0:
    bytes.setLen(bytes.len - 1)
  if bytes.len > int(int32.high):
    return writeErrVoid(WritingError(kind: weMessage, msg: $bytes.len & " isn't representable as a VarInt"))
  writeVarInt(w, newVarInt(int32(bytes.len)))
  writeSlice(w, bytes)
  writeOkVoid()

proc decodeWithVersion*(r: var NetReader, v26_3OrLater: bool): ProtoReadResult[BitSet] =
  if not v26_3OrLater:
    return decode(r)
  let lenR = getVarInt(r)
  if not lenR.isOk: return readErr[BitSet](lenR.error)
  let lenChk = checkedLen(lenR.value.value)
  if not lenChk.isOk: return readErr[BitSet](lenChk.error)
  let length = lenChk.value
  let bytesR = getFixedBitset(r, length * 8)
  if not bytesR.isOk: return readErr[BitSet](bytesR.error)
  let bytes = bytesR.value
  var arr = newSeq[int64]((length + 7) div 8)
  for wi in 0 ..< arr.len:
    var buf {.noinit.}: array[8, byte]
    for bi in 0 ..< 8:
      let idx = wi * 8 + bi
      buf[bi] = if idx < bytes.len: bytes[idx] else: 0'u8
    var u: uint64 = 0
    var shift = 0
    for bi in 0 ..< 8:
      u = u or (uint64(buf[bi]) shl uint64(shift))
      shift += 8
    arr[wi] = cast[int64](u)
  readOk[BitSet](BitSet(words: arr))
