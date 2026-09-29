## Concrete Java-edition configuration-state packet(s) beyond the smaller
## ones already in loginpackets.nim.
## Port of upstream/protocol/src/java/client/config/registry_data.rs

import protobase, netcodec, varint

type
  RegistryEntryData* = object
    ## Port of `pumpkin_data::registry::RegistryEntryData`. `data` is a
    ## caller-supplied, already-NBT-encoded byte blob (this packet writes
    ## it verbatim, it doesn't itself know or care about NBT structure) -
    ## `hasData == false` means the entry uses the registry's default/no
    ## override, matching upstream's `data: Option<Vec<u8>>`.
    entryId*: string
    hasData*: bool
    data*: seq[byte]

  CRegistryData* = object
    registryId*: string
    entries*: seq[RegistryEntryData]

proc writePacketData*(p: CRegistryData, w: var NetWriter): ProtoWriteVoidResult =
  let r1 = writeString(w, p.registryId)
  if not r1.isOk:
    return r1
  writeVarUInt(w, newVarUInt(uint32(p.entries.len)))
  for entry in p.entries:
    let r2 = writeString(w, entry.entryId)
    if not r2.isOk:
      return r2
    writeBool(w, entry.hasData)
    if entry.hasData:
      writeSlice(w, entry.data)
  writeOkVoid()

proc readPacketData*(_: typedesc[CRegistryData], r: var NetReader): ProtoReadResult[CRegistryData] =
  let idRes = getStr(r)
  if not idRes.isOk:
    return readErr[CRegistryData](idRes.error)
  let countRes = getVarUInt(r)
  if not countRes.isOk:
    return readErr[CRegistryData](countRes.error)
  var entries: seq[RegistryEntryData] = @[]
  for i in 0 ..< int(countRes.value.value):
    let entryIdRes = getStr(r)
    if not entryIdRes.isOk:
      return readErr[CRegistryData](entryIdRes.error)
    let hasDataRes = getBool(r)
    if not hasDataRes.isOk:
      return readErr[CRegistryData](hasDataRes.error)
    var blob: seq[byte] = @[]
    if hasDataRes.value:
      # Upstream reads the remainder of the packet frame as raw NBT bytes
      # here (it doesn't know the NBT's length up front, since it's
      # embedded without its own length prefix - the frame boundary IS
      # the boundary). This reader has no notion of "rest of frame", so
      # callers that need the raw blob must slice it from the frame
      # themselves; readBytesToBuf with the reader's own remaining count
      # covers the common "this entry is the last thing in the packet"
      # case, which is upstream's actual usage (config registry-data
      # packets encode exactly one entry with a data blob).
      var buf = newSeq[byte](r.data.len - r.pos)
      let readAllRes = readBytesToBuf(r, buf)
      if not readAllRes.isOk:
        return readErr[CRegistryData](readAllRes.error)
      blob = buf
    entries.add(RegistryEntryData(entryId: entryIdRes.value, hasData: hasDataRes.value, data: blob))
  readOk[CRegistryData](CRegistryData(registryId: idRes.value, entries: entries))
