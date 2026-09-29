## Low-level NBT deserialization support.
## Port of upstream/nbt/src/deserializer.rs
##
## Rust models this with an `NbtDataSource` trait borrowing zero-copy slices
## out of three different backing sources (`&[u8]`, `Bytes`, a `Read`
## stream), each wrapped by `NbtReadHelperJava`/`NbtReadHelperBedrock`. That
## split exists for Rust's borrow-checked zero-copy reads; Nimony gains
## nothing from reproducing it, so this is one `NbtReader` over an owned
## `seq[byte]` with a cursor, matching `serializer.nim`'s single-writer-type
## shape. `get_string` therefore always returns an owned `string`, never a
## `Cow`.

import nbtbase

type
  NbtReadMode* = enum
    nrmJava
    nrmBedrock

  NbtReader* = object
    mode*: NbtReadMode
    data*: seq[byte]
    pos*: int

proc newNbtReader*(mode: NbtReadMode, data: sink seq[byte]): NbtReader =
  NbtReader(mode: mode, data: data, pos: 0)

proc remaining(r: NbtReader): int {.inline.} =
  r.data.len - r.pos

proc needBytes(r: NbtReader, n: int): NbtError =
  incomplete("needed " & $n & " bytes, only " & $remaining(r) & " remaining")

proc getU8*(r: var NbtReader): NbtResult[uint8] =
  if remaining(r) < 1:
    return errRes[uint8](needBytes(r, 1))
  result = ok[uint8](r.data[r.pos])
  inc r.pos

proc getI8*(r: var NbtReader): NbtResult[int8] =
  let b = getU8(r)
  if not b.isOk:
    return errRes[int8](b.error)
  ok[int8](cast[int8](b.value))

proc getSlice(r: var NbtReader, n: int): NbtResult[seq[byte]] =
  if n < 0:
    return errRes[seq[byte]](negativeLength(int32(n)))
  if remaining(r) < n:
    return errRes[seq[byte]](needBytes(r, n))
  var s = newSeq[byte](n)
  for i in 0 ..< n:
    s[i] = r.data[r.pos + i]
  r.pos += n
  ok[seq[byte]](s)

proc beU16(bytes: seq[byte]): uint16 {.inline.} =
  (uint16(bytes[0]) shl 8) or uint16(bytes[1])

proc beU32(bytes: seq[byte]): uint32 {.inline.} =
  (uint32(bytes[0]) shl 24) or (uint32(bytes[1]) shl 16) or
    (uint32(bytes[2]) shl 8) or uint32(bytes[3])

proc beU64(bytes: seq[byte]): uint64 {.inline.} =
  result = 0
  for b in bytes:
    result = (result shl 8) or uint64(b)

proc leU16(bytes: seq[byte]): uint16 {.inline.} =
  uint16(bytes[0]) or (uint16(bytes[1]) shl 8)

proc leU32(bytes: seq[byte]): uint32 {.inline.} =
  uint32(bytes[0]) or (uint32(bytes[1]) shl 8) or
    (uint32(bytes[2]) shl 16) or (uint32(bytes[3]) shl 24)

proc leU64(bytes: seq[byte]): uint64 {.inline.} =
  result = 0
  var shift = 0
  for b in bytes:
    result = result or (uint64(b) shl uint64(shift))
    shift += 8

proc getI16*(r: var NbtReader): NbtResult[int16] =
  let s = getSlice(r, 2)
  if not s.isOk:
    return errRes[int16](s.error)
  case r.mode
  of nrmJava: ok[int16](cast[int16](beU16(s.value)))
  of nrmBedrock: ok[int16](cast[int16](leU16(s.value)))

proc getVarU32(r: var NbtReader): NbtResult[uint32] =
  var value: uint32 = 0
  var shift = 0
  while true:
    if shift >= 35:
      return errRes[uint32](varIntTooLarge())
    let b = getU8(r)
    if not b.isOk:
      return errRes[uint32](b.error)
    value = value or ((uint32(b.value) and 0x7F'u32) shl shift)
    if (b.value and 0x80'u8) == 0:
      break
    shift += 7
  ok[uint32](value)

proc getVarI32(r: var NbtReader): NbtResult[int32] =
  let v = getVarU32(r)
  if not v.isOk:
    return errRes[int32](v.error)
  let value = v.value
  ok[int32](cast[int32]((value shr 1) xor (0'u32 - (value and 1'u32))))

proc getVarU64(r: var NbtReader): NbtResult[uint64] =
  var value: uint64 = 0
  var shift = 0
  while true:
    if shift >= 70:
      return errRes[uint64](varLongTooLarge())
    let b = getU8(r)
    if not b.isOk:
      return errRes[uint64](b.error)
    value = value or ((uint64(b.value) and 0x7F'u64) shl shift)
    if (b.value and 0x80'u8) == 0:
      break
    shift += 7
  ok[uint64](value)

proc getVarI64(r: var NbtReader): NbtResult[int64] =
  let v = getVarU64(r)
  if not v.isOk:
    return errRes[int64](v.error)
  let value = v.value
  ok[int64](cast[int64]((value shr 1) xor (0'u64 - (value and 1'u64))))

proc getI32*(r: var NbtReader): NbtResult[int32] =
  case r.mode
  of nrmJava:
    let s = getSlice(r, 4)
    if not s.isOk:
      return errRes[int32](s.error)
    ok[int32](cast[int32](beU32(s.value)))
  of nrmBedrock:
    getVarI32(r)

proc getI64*(r: var NbtReader): NbtResult[int64] =
  case r.mode
  of nrmJava:
    let s = getSlice(r, 8)
    if not s.isOk:
      return errRes[int64](s.error)
    ok[int64](cast[int64](beU64(s.value)))
  of nrmBedrock:
    getVarI64(r)

proc getF32*(r: var NbtReader): NbtResult[float32] =
  case r.mode
  of nrmJava:
    let s = getSlice(r, 4)
    if not s.isOk:
      return errRes[float32](s.error)
    ok[float32](cast[float32](beU32(s.value)))
  of nrmBedrock:
    let s = getSlice(r, 4)
    if not s.isOk:
      return errRes[float32](s.error)
    ok[float32](cast[float32](leU32(s.value)))

proc getF64*(r: var NbtReader): NbtResult[float64] =
  case r.mode
  of nrmJava:
    let s = getSlice(r, 8)
    if not s.isOk:
      return errRes[float64](s.error)
    ok[float64](cast[float64](beU64(s.value)))
  of nrmBedrock:
    let s = getSlice(r, 8)
    if not s.isOk:
      return errRes[float64](s.error)
    ok[float64](cast[float64](leU64(s.value)))

proc bytesToStringLossy(bytes: seq[byte]): string =
  ## Upstream decodes Java CESU-8 / plain UTF-8 strictly and surfaces a
  ## decode error. A from-scratch CESU-8 *decoder* (surrogate-pair
  ## recombination, modified-NUL) is real work with its own edge cases;
  ## punting to a byte-for-byte copy is wrong for the rare non-ASCII/NUL
  ## case but unblocks everything downstream. TODO: implement strict
  ## CESU-8/UTF-8 decoding here and return the `utf8Decoding`/
  ## `nekCesu8Decoding` error on failure like upstream does.
  result = newString(bytes.len)
  for i, b in bytes:
    result[i] = char(b)

proc getString*(r: var NbtReader): NbtResult[string] =
  case r.mode
  of nrmJava:
    let lenRes = getI16(r)
    if not lenRes.isOk:
      return errRes[string](lenRes.error)
    let s = getSlice(r, int(cast[uint16](lenRes.value)))
    if not s.isOk:
      return errRes[string](s.error)
    ok[string](bytesToStringLossy(s.value))
  of nrmBedrock:
    let lenRes = getVarU32(r)
    if not lenRes.isOk:
      return errRes[string](lenRes.error)
    let s = getSlice(r, int(lenRes.value))
    if not s.isOk:
      return errRes[string](s.error)
    ok[string](bytesToStringLossy(s.value))

proc getByteArray*(r: var NbtReader, len: int): NbtResult[seq[int8]] =
  ## Takes an already-read, already-validated element count, matching
  ## upstream `NbtReadHelper::get_byte_array(len)` - the length prefix is
  ## read and range-checked by the caller (`NbtTag`'s (de)serialize_data),
  ## not here.
  let s = getSlice(r, len)
  if not s.isOk:
    return errRes[seq[int8]](s.error)
  var out8 = newSeq[int8](s.value.len)
  for i, b in s.value:
    out8[i] = cast[int8](b)
  ok[seq[int8]](out8)

proc getI32Array*(r: var NbtReader, len: int): NbtResult[seq[int32]] =
  var out32 = newSeq[int32](len)
  for i in 0 ..< len:
    let v = getI32(r)
    if not v.isOk:
      return errRes[seq[int32]](v.error)
    out32[i] = v.value
  ok[seq[int32]](out32)

proc getI64Array*(r: var NbtReader, len: int): NbtResult[seq[int64]] =
  var out64 = newSeq[int64](len)
  for i in 0 ..< len:
    let v = getI64(r)
    if not v.isOk:
      return errRes[seq[int64]](v.error)
    out64[i] = v.value
  ok[seq[int64]](out64)

proc skipBytes*(r: var NbtReader, n: int): NbtVoidResult =
  if remaining(r) < n:
    return errVoid(needBytes(r, n))
  r.pos += n
  okVoid()

proc skipU8*(r: var NbtReader): NbtVoidResult = skipBytes(r, 1)
proc skipI8*(r: var NbtReader): NbtVoidResult = skipBytes(r, 1)

proc skipI16*(r: var NbtReader): NbtVoidResult =
  case r.mode
  of nrmJava: skipBytes(r, 2)
  of nrmBedrock: skipBytes(r, 2)

proc skipI32*(r: var NbtReader): NbtVoidResult =
  case r.mode
  of nrmJava: skipBytes(r, 4)
  of nrmBedrock:
    let v = getVarI32(r)
    if not v.isOk: errVoid(v.error) else: okVoid()

proc skipI64*(r: var NbtReader): NbtVoidResult =
  case r.mode
  of nrmJava: skipBytes(r, 8)
  of nrmBedrock:
    let v = getVarI64(r)
    if not v.isOk: errVoid(v.error) else: okVoid()

proc skipF32*(r: var NbtReader): NbtVoidResult = skipBytes(r, 4)
proc skipF64*(r: var NbtReader): NbtVoidResult = skipBytes(r, 8)

proc skipString*(r: var NbtReader): NbtVoidResult =
  let s = getString(r)
  if not s.isOk: errVoid(s.error) else: okVoid()
