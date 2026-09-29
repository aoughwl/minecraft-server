## Points-of-interest tracking (villager job sites, nether portals, etc.).
## Port of upstream/world/src/poi/mod.rs's in-memory model and NBT
## (de)serialization. The on-disk MCA read/write (`save`/`load`, ~250 lines)
## is NOT ported here: it needs zlib, which - same gap as `nbt_compress.nim` -
## Nimony's stdlib has no module for. `buildChunkNbt`/`parseChunkNbt` below
## produce/consume the *uncompressed* NBT bytes that upstream's
## `compress_chunk_data`/`decompress_chunk_data` wrap with zlib; once
## `nbt_compress.nim`'s gzip TODO is resolved for real (it's wired to the
## sibling `compress` repo but unverified on Windows - see its own header),
## the same wiring covers POI's zlib need and `save`/`load` become a
## mechanical follow-up on top of `anvilformat.nim`'s header math.

import tick  # BlockPos
import ../nbt/tag
import ../nbt/nbtbase

const
  PoiTypeNetherPortal* = "minecraft:nether_portal"
  RegionSize = 32
  ChunkCount = RegionSize * RegionSize
  DataVersion = 3955'i32  ## upstream's hardcoded "for 1.21" constant.

type
  PoiEntry* = object
    x*, y*, z*: int32
    poiType*: string
    freeTickets*: int32

  PoiSectionData* = object
    valid*: int8
    records*: seq[PoiEntry]

  PoiChunkData* = object
    dataVersion*: int32
    sectionKeys*: seq[string]   ## parallel seqs, not a hash map - matches
    sections*: seq[PoiSectionData]  ## the ordered-compound convention
                                     ## `NbtCompound` itself already uses.

  PoiPosKey = (int32, int32, int32)

  PoiRegion* = object
    ## Entries indexed by position, matching upstream's `FxHashMap` with a
    ## Nimony `Table`. `dirtyChunks` is a plain dedup seq (chunk coordinate
    ## pairs are few compared to entries) rather than pulling in a set type.
    entries: seq[(PoiPosKey, PoiEntry)]
    dirtyChunks: seq[(int32, int32)]
    dirty*: bool

proc newPortalEntry*(pos: BlockPos): PoiEntry =
  PoiEntry(x: pos.x, y: pos.y, z: pos.z, poiType: PoiTypeNetherPortal, freeTickets: 0)

proc pos*(e: PoiEntry): BlockPos {.inline.} =
  blockPos(e.x, e.y, e.z)

proc chunkIndex*(chunkX, chunkZ: int32): int =
  ## Chunk's slot (0..1023) in an MCA file's location/timestamp tables.
  let localX = chunkX and 31
  let localZ = chunkZ and 31
  int((localZ shl 5) or localX)

proc sectionKeyOf(pos: BlockPos): string =
  ## Just the Y section coordinate, as a decimal string - matches vanilla's
  ## own POI-file section-key convention (not a full chunk-section id).
  $(pos.y shr 4)

proc newPoiRegion*(): PoiRegion =
  PoiRegion(entries: @[], dirtyChunks: @[], dirty: false)

proc findEntryIndex(r: PoiRegion, key: PoiPosKey): int =
  for i, (k, _) in r.entries:
    if k == key:
      return i
  -1

proc markChunkDirty(r: var PoiRegion, chunkX, chunkZ: int32) =
  let key = (chunkX, chunkZ)
  for c in r.dirtyChunks:
    if c == key:
      return
  r.dirtyChunks.add(key)

proc add*(r: var PoiRegion, entry: PoiEntry) =
  let chunkX = entry.x shr 4
  let chunkZ = entry.z shr 4
  markChunkDirty(r, chunkX, chunkZ)
  let key = (entry.x, entry.y, entry.z)
  let i = findEntryIndex(r, key)
  if i >= 0:
    r.entries[i][1] = entry
  else:
    r.entries.add((key, entry))
  r.dirty = true

proc remove*(r: var PoiRegion, p: BlockPos): bool =
  let key = (p.x, p.y, p.z)
  let i = findEntryIndex(r, key)
  if i < 0:
    return false
  r.entries.delete(i)
  markChunkDirty(r, p.x shr 4, p.z shr 4)
  r.dirty = true
  true

proc getAll*(r: PoiRegion): seq[PoiEntry] =
  result = @[]
  for (_, e) in r.entries:
    result.add(e)

proc markClean*(r: var PoiRegion) =
  r.dirty = false
  r.dirtyChunks = @[]

proc findOrAddSection(data: var PoiChunkData, key: string): int =
  for i, k in data.sectionKeys:
    if k == key:
      return i
  data.sectionKeys.add(key)
  data.sections.add(PoiSectionData(valid: 1, records: @[]))
  data.sectionKeys.len - 1

proc getChunkData*(r: PoiRegion, chunkX, chunkZ: int32): (bool, PoiChunkData) =
  ## Groups this region's entries by section for one chunk. Returns
  ## `(false, _)` if the chunk has no POI entries, matching upstream's
  ## `Option<PoiChunkData>`.
  var data = PoiChunkData(dataVersion: DataVersion, sectionKeys: @[], sections: @[])
  for (_, entry) in r.entries:
    if (entry.x shr 4) != chunkX or (entry.z shr 4) != chunkZ:
      continue
    let secKey = sectionKeyOf(entry.pos())
    let idx = findOrAddSection(data, secKey)
    data.sections[idx].records.add(entry)
  if data.sectionKeys.len == 0:
    (false, data)
  else:
    (true, data)

proc buildChunkNbt*(data: PoiChunkData): NbtCompound =
  ## Port of `compress_chunk_data`'s NBT-building half (the compression
  ## itself is deferred - see file header).
  var root = newCompound()
  put(root, "DataVersion", NbtTag(kind: ntkInt, intVal: data.dataVersion))
  var sectionsComp = newCompound()
  for i, secKey in data.sectionKeys:
    let sec = data.sections[i]
    var secComp = newCompound()
    put(secComp, "Valid", NbtTag(kind: ntkByte, byteVal: sec.valid))
    var recList: seq[NbtTag] = @[]
    for rec in sec.records:
      var recComp = newCompound()
      put(recComp, "x", NbtTag(kind: ntkInt, intVal: rec.x))
      put(recComp, "y", NbtTag(kind: ntkInt, intVal: rec.y))
      put(recComp, "z", NbtTag(kind: ntkInt, intVal: rec.z))
      put(recComp, "type", NbtTag(kind: ntkString, stringVal: rec.poiType))
      put(recComp, "free_tickets", NbtTag(kind: ntkInt, intVal: rec.freeTickets))
      recList.add(NbtTag(kind: ntkCompound, compoundVal: recComp))
    put(secComp, "Records", NbtTag(kind: ntkList, listVal: recList))
    put(sectionsComp, secKey, NbtTag(kind: ntkCompound, compoundVal: secComp))
  put(root, "Sections", NbtTag(kind: ntkCompound, compoundVal: sectionsComp))
  root

proc parseChunkNbt*(root: NbtCompound): PoiChunkData =
  ## Port of `decompress_chunk_data`'s NBT-parsing half. Missing/malformed
  ## fields fall back to upstream's own defaults rather than failing, since
  ## that's what `unwrap_or(...)` does throughout the Rust source.
  var dataVersion = DataVersion
  let (foundVer, verTag) = get(root, "DataVersion")
  if foundVer and verTag.kind == ntkInt:
    dataVersion = verTag.intVal

  var data = PoiChunkData(dataVersion: dataVersion, sectionKeys: @[], sections: @[])
  let (foundSections, sectionsTag) = get(root, "Sections")
  if not foundSections or sectionsTag.kind != ntkCompound:
    return data

  let sectionsComp = sectionsTag.compoundVal
  for i in 0 ..< sectionsComp.names.len:
    let secKey = sectionsComp.names[i]
    let secTag = sectionsComp.values[i]
    if secTag.kind != ntkCompound:
      continue
    let secComp = secTag.compoundVal
    var valid: int8 = 1
    let (foundValid, validTag) = get(secComp, "Valid")
    if foundValid and validTag.kind == ntkByte:
      valid = validTag.byteVal
    var records: seq[PoiEntry] = @[]
    let (foundRecs, recsTag) = get(secComp, "Records")
    if foundRecs and recsTag.kind == ntkList:
      for recTag in recsTag.listVal:
        if recTag.kind != ntkCompound:
          continue
        let rc = recTag.compoundVal
        var e = PoiEntry(x: 0, y: 0, z: 0, poiType: PoiTypeNetherPortal, freeTickets: 0)
        let (fx, xt) = get(rc, "x")
        if fx and xt.kind == ntkInt: e.x = xt.intVal
        let (fy, yt) = get(rc, "y")
        if fy and yt.kind == ntkInt: e.y = yt.intVal
        let (fz, zt) = get(rc, "z")
        if fz and zt.kind == ntkInt: e.z = zt.intVal
        let (ft, tt) = get(rc, "type")
        if ft and tt.kind == ntkString: e.poiType = tt.stringVal
        let (ff, ftt) = get(rc, "free_tickets")
        if ff and ftt.kind == ntkInt: e.freeTickets = ftt.intVal
        records.add(e)
    data.sectionKeys.add(secKey)
    data.sections.add(PoiSectionData(valid: valid, records: records))
  data
