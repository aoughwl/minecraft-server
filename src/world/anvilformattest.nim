## Round-trip smoke test for the Anvil region-file format math.
## Run with `nimony c -r src/world/anvilformattest.nim`.

import std/assertions
import std/syncio
import anvilformat

# --- region/chunk-index math ---
block:
  # Chunk (5, 3) is inside region (0, 0), at grid slot (5, 3).
  let (rx, rz) = getRegionCoords(5'i32, 3'i32)
  assert rx == 0 and rz == 0
  assert getChunkIndex(5'i32, 3'i32) == 5 + 3 * 32

  # Chunk (-1, -1) is the LAST chunk of region (-1, -1) (floor division,
  # not truncation - this is exactly the negative-coordinate trap the
  # in-file comment on floorShr warns about).
  let (rx2, rz2) = getRegionCoords(-1'i32, -1'i32)
  assert rx2 == -1 and rz2 == -1
  assert getChunkIndex(-1'i32, -1'i32) == 31 + 31 * 32

  # Chunk (-32, 0) is the FIRST chunk of region (-1, 0).
  let (rx3, _) = getRegionCoords(-32'i32, 0'i32)
  assert rx3 == -1
  assert getChunkIndex(-32'i32, 0'i32) == 0

echo "region/chunk-index math: OK"

# --- location word encode/decode ---
block:
  let loc = encodeLocation(12345'u32, 7'u8)
  assert decodeLocationOffset(loc) == 12345'u32
  assert decodeLocationCount(loc) == 7'u8

echo "location word: OK"

# --- compression byte round-trip ---
block:
  let g = compressionFromByte(1)
  assert g.kind == cbSome and g.comp == ckGZip
  assert compressionToByte(g) == 1'u8

  let none = compressionFromByte(3)
  assert none.kind == cbNone
  assert compressionToByte(none) == 3'u8

  let bad = compressionFromByte(99)
  assert bad.kind == cbInvalid

echo "compression byte: OK"

# --- per-chunk payload framing round-trip ---
block:
  let payload = AnvilChunkPayload(
    compression: compressionFromByte(3), # "no compression" - avoids the
                                          # unported gzip/zlib/LZ4 bodies
                                          # while still exercising real
                                          # length-prefix/tag framing.
    data: @[1'u8, 2, 3, 4, 5, 250, 251, 252])
  let framed = framePayload(payload)
  # 4-byte length + 1-byte tag + 8 payload bytes.
  assert framed.len == 13
  let unframedRes = unframePayload(framed)
  assert unframedRes.isOk
  let back = unframedRes.value
  assert back.compression.kind == cbNone
  assert back.data == payload.data

  # A truncated frame must fail cleanly, not read out of bounds.
  let truncatedRes = unframePayload(framed[0 ..< 6])
  assert not truncatedRes.isOk

echo "payload framing: OK"

# --- 8 KiB region header round-trip ---
block:
  var entries = newSeq[RegionChunkEntry](ChunkCount)
  for i in 0 ..< ChunkCount:
    entries[i] = RegionChunkEntry(present: false)
  entries[getChunkIndex(0, 0)] = RegionChunkEntry(
    present: true, sectorOffset: 2'u32, sectorCount: 3'u8, timestamp: 1_700_000_000'u32)
  entries[getChunkIndex(31, 31)] = RegionChunkEntry(
    present: true, sectorOffset: 5'u32, sectorCount: 1'u8, timestamp: 1_700_000_100'u32)

  let headerRes = buildRegionHeader(entries)
  assert headerRes.isOk
  let header = headerRes.value
  assert header.len == 2 * SectorBytes

  let parsedRes = parseRegionHeader(header)
  assert parsedRes.isOk
  let parsed = parsedRes.value
  assert parsed.len == ChunkCount
  assert parsed[getChunkIndex(0, 0)].present
  assert parsed[getChunkIndex(0, 0)].sectorOffset == 2'u32
  assert parsed[getChunkIndex(0, 0)].sectorCount == 3'u8
  assert parsed[getChunkIndex(0, 0)].timestamp == 1_700_000_000'u32
  assert parsed[getChunkIndex(31, 31)].sectorCount == 1'u8
  # An untouched slot must round-trip as absent, not garbage.
  assert not parsed[getChunkIndex(1, 1)].present

  # sectorOffset < 2 is reserved for the header itself - must decode as
  # absent even if a location word happens to be nonzero there (the same
  # guard upstream's real reader applies).
  var badLoc = newSeq[byte](2 * SectorBytes)
  # location word for slot 0: offset=1 (invalid), count=1
  badLoc[0] = 0; badLoc[1] = 0; badLoc[2] = 1; badLoc[3] = 1
  let badParsed = parseRegionHeader(badLoc)
  assert badParsed.isOk
  assert not badParsed.value[0].present

  let wrongSizeRes = parseRegionHeader(header[0 ..< 100])
  assert not wrongSizeRes.isOk

echo "region header: OK"

# --- sector-size math ---
block:
  # 0 payload bytes -> still 1 sector (4-byte length + 1-byte tag rounds
  # up from 5 bytes to one 4096-byte sector).
  assert sectorCountFor(0) == 1'u32
  assert paddedSizeFor(0) == SectorBytes
  # Exactly filling N sectors' worth of raw bytes must not spill into an
  # extra sector, and one byte more must.
  let exact = SectorBytes * 3 - 5 # so raw_write_size == 3 sectors exactly
  assert sectorCountFor(exact) == 3'u32
  assert sectorCountFor(exact + 1) == 4'u32

echo "sector math: OK"

echo "all anvil-format round-trip checks passed"
