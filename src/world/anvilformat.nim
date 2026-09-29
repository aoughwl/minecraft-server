## The Java Edition on-disk region file (.mca "Anvil") format: the 8 KiB
## location/timestamp header, per-chunk sector accounting, and the
## length-prefixed/compression-tagged chunk payload framing.
## Port of the pure on-disk-layout portion of upstream/world/src/chunk/format/anvil.rs.
##
## Scope: this file ports the FORMAT MATH ONLY - the byte-level header
## layout, sector bookkeeping, and payload framing that decide where a
## chunk's bytes live in a region file and how its length/compression tag
## is encoded. It deliberately does NOT port:
##   - actual gzip/zlib/LZ4 (de)compression bodies: same gap as
##     src/nbt/nbt_compress.nim (no zlib/gzip module in Nimony's stdlib);
##     `CompressionKind` here still tags a chunk's declared method, this
##     file just doesn't decode/encode the compressed bytes themselves.
##   - the async file I/O / mutex-guarded in-place sector allocator
##     (`AnvilChunkFile::write`/`write_indices`, tokio `AsyncWrite`) - no
##     concurrency/async design has been chosen yet for this port (the
##     same gap flagged for the scheduler and plugin runtime).
## Those are real follow-ups, not silently skipped: this layer (framing +
## header math) is exactly what upstream's own `palette.rs` fork called
## out as "a separate mechanical follow-up now the in-memory shape is
## settled", and it's self-contained enough to verify with a real
## round-trip test (see anvilformattest.nim) without either gap.

import ../nbt/nbtbase

const
  RegionSize* = 32                      ## one region is 32x32 chunks
  SubregionBits = 5'i32                 ## ceil_log2(32)
  SubregionAnd = (1'i32 shl SubregionBits) - 1
  ChunkCount* = RegionSize * RegionSize
  SectorBytes* = 4096
  NoCompressionId = 3'u8
  WorldDataVersion* = 4903

type
  CompressionKind* = enum
    ckGZip = 1
    ckZLib = 2
    ckLZ4 = 4
    ckCustom = 127

  CompressionByteKind* = enum
    cbInvalid    ## unrecognized byte
    cbNone       ## valid, explicitly "no compression"
    cbSome       ## valid, names a known compression method

  CompressionByteResult* = object
    ## Mirrors upstream's `Compression::from_byte -> Result<Option<Self>, ()>`:
    ## three outcomes, not two - a byte can name a known compression, name
    ## "no compression" (id 3, valid but not a `Compression` variant), or
    ## be an unrecognized id (an error).
    case kind*: CompressionByteKind
    of cbInvalid, cbNone: discard
    of cbSome: comp*: CompressionKind

proc compressionFromByte*(b: uint8): CompressionByteResult =
  case b
  of ord(ckGZip).uint8: CompressionByteResult(kind: cbSome, comp: ckGZip)
  of ord(ckZLib).uint8: CompressionByteResult(kind: cbSome, comp: ckZLib)
  of NoCompressionId: CompressionByteResult(kind: cbNone)
  of ord(ckLZ4).uint8: CompressionByteResult(kind: cbSome, comp: ckLZ4)
  of ord(ckCustom).uint8: CompressionByteResult(kind: cbSome, comp: ckCustom)
  else: CompressionByteResult(kind: cbInvalid)

proc compressionToByte*(r: CompressionByteResult): uint8 =
  case r.kind
  of cbNone: NoCompressionId
  of cbSome: ord(r.comp).uint8
  of cbInvalid: 0'u8 # caller error, not a valid encode input

# --- region/chunk-index math -------------------------------------------

proc floorShr(x: int32, bits: int32): int32 {.inline.} =
  ## Rust's `x >> SUBREGION_BITS` on a signed i32 is an arithmetic shift,
  ## which is floor division by a power of two (rounds toward -inf, not
  ## zero) - Nimony's `shr` on a *signed* int is likewise arithmetic, so
  ## this is a direct port, spelled out because getting the rounding
  ## direction wrong here silently misfiles every chunk in a negative
  ## region coordinate.
  x shr bits

proc getRegionCoords*(chunkX, chunkZ: int32): (int32, int32) =
  let rx = floorShr(chunkX, SubregionBits)
  let rz = floorShr(chunkZ, SubregionBits)
  (rx, rz)

proc getChunkIndex*(chunkX, chunkZ: int32): int =
  ## Position of a chunk within its region's 32x32 grid, index into the
  ## 1024-entry location/timestamp tables.
  int((chunkX and SubregionAnd) + (chunkZ and SubregionAnd) * RegionSize.int32)

# --- per-chunk sector accounting ----------------------------------------

proc sectorCountFor*(compressedLen: int): uint32 =
  ## `raw_write_size` (4-byte length + 1-byte compression tag + payload),
  ## rounded up to whole 4 KiB sectors.
  let rawWriteSize = compressedLen + 4 + 1
  uint32((rawWriteSize + SectorBytes - 1) div SectorBytes)

proc paddedSizeFor*(compressedLen: int): int =
  int(sectorCountFor(compressedLen)) * SectorBytes

# --- location-table entry (u32 = (sectorOffset << 8) | sectorCount) -----

proc encodeLocation*(sectorOffset: uint32, sectorCount: uint8): uint32 {.inline.} =
  (sectorOffset shl 8) or sectorCount.uint32

proc decodeLocationOffset*(location: uint32): uint32 {.inline.} =
  location shr 8

proc decodeLocationCount*(location: uint32): uint8 {.inline.} =
  uint8(location and 0xFF'u32)

# --- 8 KiB region-file header (location table + timestamp table) --------

type
  RegionChunkEntry* = object
    present*: bool     ## false = this chunk slot is empty (location word 0)
    sectorOffset*: uint32
    sectorCount*: uint8
    timestamp*: uint32

proc readBE32(data: openArray[byte], pos: int): uint32 {.inline.} =
  (uint32(data[pos]) shl 24) or (uint32(data[pos+1]) shl 16) or
    (uint32(data[pos+2]) shl 8) or uint32(data[pos+3])

proc writeBE32(data: var seq[byte], pos: int, value: uint32) {.inline.} =
  data[pos] = uint8(value shr 24)
  data[pos+1] = uint8((value shr 16) and 0xFF'u32)
  data[pos+2] = uint8((value shr 8) and 0xFF'u32)
  data[pos+3] = uint8(value and 0xFF'u32)

proc parseRegionHeader*(headerBytes: openArray[byte]): NbtResult[seq[RegionChunkEntry]] =
  ## `headerBytes` must be exactly `2 * SectorBytes` (8192) bytes: the
  ## location table (1024 big-endian u32s) followed by the timestamp
  ## table (1024 big-endian u32s), per upstream's `AnvilChunkFile::read`.
  ## Sector 0 and sector 1 are reserved for these two tables, so a chunk
  ## can never legitimately claim `sectorOffset < 2`; upstream treats
  ## that (and a zero location word) as "absent", which this mirrors.
  if headerBytes.len != 2 * SectorBytes:
    return errRes[seq[RegionChunkEntry]](
      nbtError(nekIncomplete, "region header must be exactly " & $(2 * SectorBytes) & " bytes"))
  var entries = newSeq[RegionChunkEntry](ChunkCount)
  for i in 0 ..< ChunkCount:
    let location = readBE32(headerBytes, i * 4)
    let timestamp = readBE32(headerBytes, SectorBytes + i * 4)
    let sectorCount = decodeLocationCount(location)
    let sectorOffset = decodeLocationOffset(location)
    if location == 0 or sectorOffset < 2:
      entries[i] = RegionChunkEntry(present: false)
    else:
      entries[i] = RegionChunkEntry(
        present: true, sectorOffset: sectorOffset, sectorCount: sectorCount, timestamp: timestamp)
  ok[seq[RegionChunkEntry]](entries)

proc buildRegionHeader*(entries: openArray[RegionChunkEntry]): NbtResult[seq[byte]] =
  if entries.len != ChunkCount:
    return errRes[seq[byte]](
      nbtError(nekIncomplete, "expected exactly " & $ChunkCount & " region entries"))
  var header = newSeq[byte](2 * SectorBytes)
  for i in 0 ..< ChunkCount:
    let e = entries[i]
    let location =
      if e.present: encodeLocation(e.sectorOffset, e.sectorCount)
      else: 0'u32
    writeBE32(header, i * 4, location)
    writeBE32(header, SectorBytes + i * 4, if e.present: e.timestamp else: 0'u32)
  ok[seq[byte]](header)

# --- per-chunk payload framing (length + compression tag + bytes) -------

type
  AnvilChunkPayload* = object
    compression*: CompressionByteResult
    data*: seq[byte]   ## the (still-compressed, if `compression.kind == cbSome`) payload bytes

proc framePayload*(p: AnvilChunkPayload): seq[byte] =
  ## `declaredLength` covers the compression byte plus the payload, per
  ## upstream's `AnvilChunkData::write` (`compressed_data.len() + 1`).
  let declaredLength = uint32(p.data.len + 1)
  result = newSeq[byte](4 + 1 + p.data.len)
  writeBE32(result, 0, declaredLength)
  result[4] = compressionToByte(p.compression)
  for i, b in p.data:
    result[5 + i] = b

proc unframePayload*(bytes: openArray[byte]): NbtResult[AnvilChunkPayload] =
  if bytes.len < 5:
    return errRes[AnvilChunkPayload](nbtError(nekIncomplete, "chunk payload shorter than its own header"))
  let declaredLength = readBE32(bytes, 0)
  if declaredLength == 0:
    return errRes[AnvilChunkPayload](
      nbtError(nekIncomplete, "chunk length does not cover its compression byte"))
  let length = int(declaredLength) - 1
  if length > bytes.len - 5:
    return errRes[AnvilChunkPayload](
      nbtError(nekIncomplete, "chunk length is greater than available bytes"))
  let compByte = bytes[4]
  let comp = compressionFromByte(compByte)
  if comp.kind == cbInvalid:
    return errRes[AnvilChunkPayload](unknownTagId(compByte))
  var data = newSeq[byte](length)
  for i in 0 ..< length:
    data[i] = bytes[5 + i]
  ok[AnvilChunkPayload](AnvilChunkPayload(compression: comp, data: data))
