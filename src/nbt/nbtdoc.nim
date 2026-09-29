## A complete NBT document: a named root compound, plus its top-level
## read/write entry points.
## Port of pumpkingmc/crates/pumpkin-nbt/src/lib.rs's `Nbt` struct.

import nbtbase, serializer, deserializer, tag

type
  Nbt* = object
    name*: string
    rootTag*: NbtCompound

proc newNbt*(name: string, tag: sink NbtCompound): Nbt =
  Nbt(name: name, rootTag: tag)

proc read*(r: var NbtReader): NbtResult[Nbt] =
  ## Reads a named NBT document. Errors with `noRootCompound` if the first
  ## tag isn't a compound.
  let idRes = getU8(r)
  if not idRes.isOk:
    return errRes[Nbt](idRes.error)
  if idRes.value != CompoundId:
    return errRes[Nbt](noRootCompound(idRes.value))
  let nameRes = getString(r)
  if not nameRes.isOk:
    return errRes[Nbt](nameRes.error)
  let contentRes = deserializeContent(r)
  if not contentRes.isOk:
    return errRes[Nbt](contentRes.error)
  ok[Nbt](Nbt(name: nameRes.value, rootTag: contentRes.value))

proc readUnnamed*(r: var NbtReader): NbtResult[Nbt] =
  ## Reads an NBT document that omits the root compound's name. The
  ## returned document has an empty `name`.
  let idRes = getU8(r)
  if not idRes.isOk:
    return errRes[Nbt](idRes.error)
  if idRes.value != CompoundId:
    return errRes[Nbt](noRootCompound(idRes.value))
  let contentRes = deserializeContent(r)
  if not contentRes.isOk:
    return errRes[Nbt](contentRes.error)
  ok[Nbt](Nbt(name: "", rootTag: contentRes.value))

proc write*(doc: sink Nbt, mode: NbtWriteMode): seq[byte] =
  ## Serializes this document. `mode` selects Java (big-endian/CESU-8) or
  ## Bedrock (little-endian/varint) wire format - upstream splits this
  ## into `write`/`write_bedrock`, unified here the same way `NbtWriter`
  ## unifies the two writer trait impls.
  ##
  ## Matches upstream's own leniency: on any write failure, this returns
  ## whatever was written so far rather than propagating an error (Rust's
  ## `Nbt::write` silently discards the `Result` from a failed
  ## `write_u8`/`serialize_data`/`serialize_content` call for the same
  ## reason - by construction here, a `seq[byte]` writer can't actually
  ## fail, so the discard is moot, but the shape is kept for fidelity).
  var w = newNbtWriter(mode)
  w.writeU8(CompoundId)
  let nameTag = NbtTag(kind: ntkString, stringVal: doc.name)
  discard serializeData(nameTag, w)
  discard serializeContent(doc.rootTag, w)
  w.buf

proc writeUnnamed*(doc: sink Nbt, mode: NbtWriteMode): seq[byte] =
  var w = newNbtWriter(mode)
  w.writeU8(CompoundId)
  discard serializeContent(doc.rootTag, w)
  w.buf
