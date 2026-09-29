## In-memory representation of individual NBT tags, plus compound-tag
## (de)serialization content.
## Port of upstream/nbt/src/tag.rs and (the content-level
## procs of) src/compound.rs. Both live in this file because `NbtTag`'s
## serialize/deserialize recurses into `NbtCompound`'s and vice versa;
## Rust resolves that with two modules and `pub(crate)` visibility, Nimony
## resolves it more simply by not splitting the cycle across files.

import nbtbase, serializer, deserializer

type
  NbtTagKind* = enum
    ntkEnd = 0'u8
    ntkByte = 1'u8
    ntkShort = 2'u8
    ntkInt = 3'u8
    ntkLong = 4'u8
    ntkFloat = 5'u8
    ntkDouble = 6'u8
    ntkByteArray = 7'u8
    ntkString = 8'u8
    ntkList = 9'u8
    ntkCompound = 10'u8
    ntkIntArray = 11'u8
    ntkLongArray = 12'u8

  NbtTag* = object
    case kind*: NbtTagKind
    of ntkEnd: discard
    of ntkByte: byteVal*: int8
    of ntkShort: shortVal*: int16
    of ntkInt: intVal*: int32
    of ntkLong: longVal*: int64
    of ntkFloat: floatVal*: float32
    of ntkDouble: doubleVal*: float64
    of ntkByteArray: byteArrayVal*: seq[int8]
    of ntkString: stringVal*: string
    of ntkList: listVal*: seq[NbtTag]
    of ntkCompound: compoundVal*: NbtCompound
    of ntkIntArray: intArrayVal*: seq[int32]
    of ntkLongArray: longArrayVal*: seq[int64]

  NbtCompound* = object
    ## Insertion-ordered map of name -> NbtTag.
    ## Rust's `NbtCompound.child_tags` is an IndexMap; Nimony has no stdlib
    ## ordered map yet, so this keeps parallel `names`/`values` seqs and does
    ## a linear scan on lookup. Fine for the compound sizes NBT tags contain
    ## (chunk sections, entities, item components); revisit if it shows up
    ## as a hot path once the deserializer is ported.
    names*: seq[string]
    values*: seq[NbtTag]

proc getTypeId*(tag: NbtTag): uint8 {.inline.} =
  ord(tag.kind).uint8

proc newCompound*(): NbtCompound =
  NbtCompound(names: @[], values: @[])

proc len*(c: NbtCompound): int {.inline.} =
  c.names.len

proc indexOf(c: NbtCompound, name: string): int =
  for i, n in c.names:
    if n == name:
      return i
  result = -1

proc containsKey*(c: NbtCompound, name: string): bool {.inline.} =
  indexOf(c, name) >= 0

proc put*(c: var NbtCompound, name: string, tag: NbtTag) =
  let i = indexOf(c, name)
  if i >= 0:
    c.values[i] = tag
  else:
    c.names.add(name)
    c.values.add(tag)

proc get*(c: NbtCompound, name: string): (bool, NbtTag) =
  let i = indexOf(c, name)
  if i >= 0:
    (true, c.values[i])
  else:
    (false, NbtTag(kind: ntkEnd))

proc remove*(c: var NbtCompound, name: string): (bool, NbtTag) =
  ## Port of `IndexMap::remove` as used by `NbtTag::flatten`: removes and
  ## returns the value, if present.
  let i = indexOf(c, name)
  if i >= 0:
    result = (true, c.values[i])
    c.names.delete(i)
    c.values.delete(i)
  else:
    result = (false, NbtTag(kind: ntkEnd))

proc getListElementTypeId(list: seq[NbtTag]): uint8 =
  ## If any elements differ in type, upstream falls back to COMPOUND_ID
  ## (matching how a heterogeneous list gets wrapped on write).
  var elementId = ord(ntkEnd).uint8
  for tag in list:
    let id = tag.getTypeId()
    if elementId == ord(ntkEnd).uint8:
      elementId = id
    elif elementId != id:
      return ord(ntkCompound).uint8
  elementId

proc isWrapperCompound(c: NbtCompound): bool {.inline.} =
  ## A *wrapper compound* stores exactly one key-value pair under the empty
  ## string key `""`.
  c.len == 1 and c.containsKey("")

proc flatten*(tag: sink NbtTag): NbtTag =
  ## Tries to unwrap (flatten) a wrapped `NbtTag`. If no unwrap is possible,
  ## returns the tag unchanged.
  if tag.kind == ntkCompound:
    var compound = tag.compoundVal
    if isWrapperCompound(compound):
      let (found, inner) = remove(compound, "")
      if found:
        return inner
    NbtTag(kind: ntkCompound, compoundVal: compound)
  else:
    tag

proc wrapTag*(tag: sink NbtTag): NbtTag =
  var compound = newCompound()
  put(compound, "", tag)
  NbtTag(kind: ntkCompound, compoundVal: compound)

proc wrapTagIfNeeded*(elementType: uint8, tag: sink NbtTag): NbtTag =
  if elementType == ord(ntkCompound).uint8:
    if tag.kind == ntkCompound and not isWrapperCompound(tag.compoundVal):
      tag
    else:
      wrapTag(tag)
  else:
    tag

# --- serialize_data / serialize_content -------------------------------


proc serializeContent*(c: NbtCompound, w: var NbtWriter): NbtVoidResult =
  ## Port of `NbtCompound::serialize_content`.
  for i in 0 ..< c.names.len:
    w.writeU8(c.values[i].getTypeId())
    let nameRes = w.writeString(c.names[i])
    if not nameRes.isOk:
      return nameRes
    let valRes = serializeData(c.values[i], w)
    if not valRes.isOk:
      return valRes
  w.writeU8(EndId)
  okVoid()

proc serializeData*(tag: NbtTag, w: var NbtWriter): NbtVoidResult =
  case tag.kind
  of ntkEnd:
    discard
  of ntkByte:
    w.writeI8(tag.byteVal)
  of ntkShort:
    w.writeI16(tag.shortVal)
  of ntkInt:
    w.writeI32(tag.intVal)
  of ntkLong:
    w.writeI64(tag.longVal)
  of ntkFloat:
    w.writeF32(tag.floatVal)
  of ntkDouble:
    w.writeF64(tag.doubleVal)
  of ntkByteArray:
    let len = tag.byteArrayVal.len
    if len > int(int32.high):
      return errVoid(largeLength(len))
    w.writeI32(int32(len))
    for b in tag.byteArrayVal:
      w.writeU8(cast[uint8](b))
  of ntkString:
    let r = w.writeString(tag.stringVal)
    if not r.isOk:
      return r
  of ntkList:
    let len = tag.listVal.len
    if len > int(int32.high):
      return errVoid(largeLength(len))
    let elemId = getListElementTypeId(tag.listVal)
    w.writeU8(elemId)
    w.writeI32(int32(len))
    for t in tag.listVal:
      # Tags within one list tag must share a type; heterogeneous elements
      # get wrapped in a single-entry NbtCompound so the stream stays valid.
      let wrapped = wrapTagIfNeeded(elemId, t)
      let r = serializeData(wrapped, w)
      if not r.isOk:
        return r
  of ntkCompound:
    let r = serializeContent(tag.compoundVal, w)
    if not r.isOk:
      return r
  of ntkIntArray:
    let len = tag.intArrayVal.len
    if len > int(int32.high):
      return errVoid(largeLength(len))
    w.writeI32(int32(len))
    for v in tag.intArrayVal:
      w.writeI32(v)
  of ntkLongArray:
    let len = tag.longArrayVal.len
    if len > int(int32.high):
      return errVoid(largeLength(len))
    w.writeI32(int32(len))
    for v in tag.longArrayVal:
      w.writeI64(v)
  okVoid()

proc serialize*(tag: NbtTag, w: var NbtWriter): NbtVoidResult =
  ## Serializes the tag's type ID followed by its payload.
  w.writeU8(tag.getTypeId())
  serializeData(tag, w)

# --- deserialize_data_depth / deserialize_content_depth ----------------


proc deserializeContentDepth*(r: var NbtReader, depth: int): NbtResult[NbtCompound] =
  ## Port of `NbtCompound::deserialize_content_depth`.
  if depth > MaxNbtDepth:
    return errRes[NbtCompound](maxDepthExceeded())
  var compound = newCompound()
  while true:
    let idRes = getU8(r)
    if not idRes.isOk:
      # Upstream treats an unexpected-EOF here as "no more tags" (the root
      # document's trailing END tag is optional on some sources); any other
      # read failure still propagates.
      break
    let tagId = idRes.value
    if tagId == EndId:
      break
    let nameRes = getString(r)
    if not nameRes.isOk:
      return errRes[NbtCompound](nameRes.error)
    let tagRes = deserializeDataDepth(r, tagId, depth + 1)
    if not tagRes.isOk:
      return errRes[NbtCompound](tagRes.error)
    put(compound, nameRes.value, tagRes.value)
  ok[NbtCompound](compound)

proc deserializeContent*(r: var NbtReader): NbtResult[NbtCompound] =
  deserializeContentDepth(r, 0)

proc deserializeDataDepth*(r: var NbtReader, tagId: uint8, depth: int): NbtResult[NbtTag] =
  if depth > MaxNbtDepth:
    return errRes[NbtTag](maxDepthExceeded())
  case tagId
  of EndId:
    ok[NbtTag](NbtTag(kind: ntkEnd))
  of ByteId:
    let v = getI8(r)
    if not v.isOk: errRes[NbtTag](v.error)
    else: ok[NbtTag](NbtTag(kind: ntkByte, byteVal: v.value))
  of ShortId:
    let v = getI16(r)
    if not v.isOk: errRes[NbtTag](v.error)
    else: ok[NbtTag](NbtTag(kind: ntkShort, shortVal: v.value))
  of IntId:
    let v = getI32(r)
    if not v.isOk: errRes[NbtTag](v.error)
    else: ok[NbtTag](NbtTag(kind: ntkInt, intVal: v.value))
  of LongId:
    let v = getI64(r)
    if not v.isOk: errRes[NbtTag](v.error)
    else: ok[NbtTag](NbtTag(kind: ntkLong, longVal: v.value))
  of FloatId:
    let v = getF32(r)
    if not v.isOk: errRes[NbtTag](v.error)
    else: ok[NbtTag](NbtTag(kind: ntkFloat, floatVal: v.value))
  of DoubleId:
    let v = getF64(r)
    if not v.isOk: errRes[NbtTag](v.error)
    else: ok[NbtTag](NbtTag(kind: ntkDouble, doubleVal: v.value))
  of ByteArrayId:
    let lenRes = getI32(r)
    if not lenRes.isOk: return errRes[NbtTag](lenRes.error)
    if lenRes.value < 0: return errRes[NbtTag](negativeLength(lenRes.value))
    if int(lenRes.value) > MaxArrayLength: return errRes[NbtTag](largeLength(int(lenRes.value)))
    let arr = getByteArray(r, int(lenRes.value))
    if not arr.isOk: errRes[NbtTag](arr.error)
    else: ok[NbtTag](NbtTag(kind: ntkByteArray, byteArrayVal: arr.value))
  of StringId:
    let v = getString(r)
    if not v.isOk: errRes[NbtTag](v.error)
    else: ok[NbtTag](NbtTag(kind: ntkString, stringVal: v.value))
  of ListId:
    let elemIdRes = getU8(r)
    if not elemIdRes.isOk: return errRes[NbtTag](elemIdRes.error)
    let elemId = elemIdRes.value
    let lenRes = getI32(r)
    if not lenRes.isOk: return errRes[NbtTag](lenRes.error)
    if lenRes.value < 0: return errRes[NbtTag](negativeLength(lenRes.value))
    if elemId == EndId and lenRes.value > 0: return errRes[NbtTag](invalidListTag(elemId))
    let n = int(lenRes.value)
    if n > MaxArrayLength: return errRes[NbtTag](largeLength(n))
    var list = newSeq[NbtTag](0)
    for _ in 0 ..< n:
      let elemRes = deserializeDataDepth(r, elemId, depth + 1)
      if not elemRes.isOk: return errRes[NbtTag](elemRes.error)
      if elemRes.value.getTypeId() != elemId:
        return errRes[NbtTag](invalidListTag(elemRes.value.getTypeId()))
      list.add(flatten(elemRes.value))
    ok[NbtTag](NbtTag(kind: ntkList, listVal: list))
  of CompoundId:
    let c = deserializeContentDepth(r, depth + 1)
    if not c.isOk: errRes[NbtTag](c.error)
    else: ok[NbtTag](NbtTag(kind: ntkCompound, compoundVal: c.value))
  of IntArrayId:
    let lenRes = getI32(r)
    if not lenRes.isOk: return errRes[NbtTag](lenRes.error)
    if lenRes.value < 0: return errRes[NbtTag](negativeLength(lenRes.value))
    if int(lenRes.value) > MaxArrayLength: return errRes[NbtTag](largeLength(int(lenRes.value)))
    let arr = getI32Array(r, int(lenRes.value))
    if not arr.isOk: errRes[NbtTag](arr.error)
    else: ok[NbtTag](NbtTag(kind: ntkIntArray, intArrayVal: arr.value))
  of LongArrayId:
    let lenRes = getI32(r)
    if not lenRes.isOk: return errRes[NbtTag](lenRes.error)
    if lenRes.value < 0: return errRes[NbtTag](negativeLength(lenRes.value))
    if int(lenRes.value) > MaxArrayLength: return errRes[NbtTag](largeLength(int(lenRes.value)))
    let arr = getI64Array(r, int(lenRes.value))
    if not arr.isOk: errRes[NbtTag](arr.error)
    else: ok[NbtTag](NbtTag(kind: ntkLongArray, longArrayVal: arr.value))
  else:
    errRes[NbtTag](unknownTagId(tagId))

proc deserialize*(r: var NbtReader): NbtResult[NbtTag] =
  let idRes = getU8(r)
  if not idRes.isOk:
    return errRes[NbtTag](idRes.error)
  deserializeDataDepth(r, idRes.value, 0)

# --- skip_data_depth / skip_content_depth -------------------------------


proc skipContentDepth*(r: var NbtReader, depth: int): NbtVoidResult =
  if depth > MaxNbtDepth:
    return errVoid(maxDepthExceeded())
  while true:
    let idRes = getU8(r)
    if not idRes.isOk:
      break
    let tagId = idRes.value
    if tagId == EndId:
      break
    let sRes = skipString(r)
    if not sRes.isOk:
      return sRes
    let vRes = skipDataDepth(r, tagId, depth + 1)
    if not vRes.isOk:
      return vRes
  okVoid()

proc skipContent*(r: var NbtReader): NbtVoidResult =
  skipContentDepth(r, 0)

proc skipDataDepth*(r: var NbtReader, tagId: uint8, depth: int): NbtVoidResult =
  if depth > MaxNbtDepth:
    return errVoid(maxDepthExceeded())
  case tagId
  of EndId: okVoid()
  of ByteId: skipI8(r)
  of ShortId: skipI16(r)
  of IntId: skipI32(r)
  of LongId: skipI64(r)
  of FloatId: skipF32(r)
  of DoubleId: skipF64(r)
  of ByteArrayId:
    let lenRes = getI32(r)
    if not lenRes.isOk: return errVoid(lenRes.error)
    if lenRes.value < 0: return errVoid(negativeLength(lenRes.value))
    if int(lenRes.value) > MaxArrayLength: return errVoid(largeLength(int(lenRes.value)))
    skipBytes(r, int(lenRes.value))
  of StringId: skipString(r)
  of ListId:
    let elemIdRes = getU8(r)
    if not elemIdRes.isOk: return errVoid(elemIdRes.error)
    let elemId = elemIdRes.value
    let lenRes = getI32(r)
    if not lenRes.isOk: return errVoid(lenRes.error)
    if lenRes.value < 0: return errVoid(negativeLength(lenRes.value))
    if elemId == EndId and lenRes.value > 0: return errVoid(invalidListTag(elemId))
    let n = int(lenRes.value)
    if n > MaxArrayLength: return errVoid(largeLength(n))
    for _ in 0 ..< n:
      let r2 = skipDataDepth(r, elemId, depth + 1)
      if not r2.isOk: return r2
    okVoid()
  of CompoundId:
    skipContentDepth(r, depth + 1)
  of IntArrayId:
    let lenRes = getI32(r)
    if not lenRes.isOk: return errVoid(lenRes.error)
    if lenRes.value < 0: return errVoid(negativeLength(lenRes.value))
    if int(lenRes.value) > MaxArrayLength: return errVoid(largeLength(int(lenRes.value)))
    for _ in 0 ..< int(lenRes.value):
      let r2 = skipI32(r)
      if not r2.isOk: return r2
    okVoid()
  of LongArrayId:
    let lenRes = getI32(r)
    if not lenRes.isOk: return errVoid(lenRes.error)
    if lenRes.value < 0: return errVoid(negativeLength(lenRes.value))
    if int(lenRes.value) > MaxArrayLength: return errVoid(largeLength(int(lenRes.value)))
    for _ in 0 ..< int(lenRes.value):
      let r2 = skipI64(r)
      if not r2.isOk: return r2
    okVoid()
  else:
    errVoid(unknownTagId(tagId))

proc skipData*(r: var NbtReader, tagId: uint8): NbtVoidResult =
  skipDataDepth(r, tagId, 0)

