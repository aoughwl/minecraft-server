## In-memory representation of individual NBT tags.
## Port of pumpkingmc/crates/pumpkin-nbt/src/tag.rs

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
