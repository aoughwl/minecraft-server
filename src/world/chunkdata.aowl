## In-memory chunk data model: heightmaps and per-section block/biome storage.
## Port of upstream/pumpkin-world/src/chunk/mod.rs's `ChunkHeightmaps` and
## `ChunkSections` (the "which chunks are loaded, how do I look one up"
## shape asked for - NOT the full `ChunkData`, which also needs a light
## engine, blending data, and NBT (de)serialization that are separately
## scoped). Skips `RwLock`/`Mutex`/`AtomicBool` wrappers entirely: this
## port has no concurrency model decided yet (same punt as scheduler/net),
## so fields that were synchronization wrappers upstream are just plain
## fields here.

import palette

const
  SectionBlocks* = 4096 ## 16*16*16
  SectionBiomes* = 64   ## 4*4*4 (biomes are quantized to 4-block cells)
  HeightmapColumns* = 256 ## 16*16, one value per (x, z) column
  HeightmapWords* = 37 ## ceil(256 / 7), 9 bits per value packed into i64 words

type
  ChunkHeightmapType* = enum
    chmWorldSurface = 0
    chmMotionBlocking = 1
    chmMotionBlockingNoLeaves = 2

  ChunkHeightmaps* = object
    worldSurface*: seq[int64]           ## empty seq == "not yet computed" (upstream's None)
    motionBlocking*: seq[int64]
    motionBlockingNoLeaves*: seq[int64]

  ChunkSections* = object
    count*: int
    blockSections*: seq[PalettedContainer]
    biomeSections*: seq[PalettedContainer]
    minY*: int32

proc newChunkHeightmaps*(): ChunkHeightmaps =
  ChunkHeightmaps(worldSurface: @[], motionBlocking: @[], motionBlockingNoLeaves: @[])

proc heightmapFieldConst(h: ChunkHeightmaps, kind: ChunkHeightmapType): seq[int64] =
  case kind
  of chmWorldSurface: h.worldSurface
  of chmMotionBlocking: h.motionBlocking
  of chmMotionBlockingNoLeaves: h.motionBlockingNoLeaves

proc setHeightmap*(h: var ChunkHeightmaps, kind: ChunkHeightmapType, x, z, height, minY: int32) =
  ## Port of `ChunkHeightmaps::set`. 9 bits per (x,z) column, 7 columns per
  ## i64 word, so they never cross a word boundary (64 / 9 = 7).
  var data = heightmapFieldConst(h, kind)
  if data.len == 0:
    data = newSeq[int64](HeightmapWords)
  let localX = int(x and 15)
  let localZ = int(z and 15)
  let columnIdx = localZ * 16 + localX
  let val = uint64(max(height - minY + 1, 0'i32))

  let arrayIdx = columnIdx div 7
  let shift = uint64((columnIdx mod 7) * 9)
  let mask = 0x1FF'u64 shl shift

  var current = cast[uint64](data[arrayIdx])
  current = (current and (not mask)) or ((val and 0x1FF'u64) shl shift)
  data[arrayIdx] = cast[int64](current)

  case kind
  of chmWorldSurface: h.worldSurface = data
  of chmMotionBlocking: h.motionBlocking = data
  of chmMotionBlockingNoLeaves: h.motionBlockingNoLeaves = data

proc getHeightmap*(h: ChunkHeightmaps, kind: ChunkHeightmapType, x, z, minY: int32): int32 =
  ## Port of `ChunkHeightmaps::get`.
  let data = heightmapFieldConst(h, kind)
  if data.len == 0:
    return minY - 1
  let localX = int(x and 15)
  let localZ = int(z and 15)
  let columnIdx = localZ * 16 + localX
  let arrayIdx = columnIdx div 7
  let shift = uint64((columnIdx mod 7) * 9)
  let current = cast[uint64](data[arrayIdx])
  let val = (current shr shift) and 0x1FF'u64
  int32(val) + minY - 1

proc newChunkSections*(count: int, minY: int32, defaultBlock, defaultBiome: PaletteValue): ChunkSections =
  ## `count` is the number of 16-block-tall subchunk sections (vanilla
  ## Overworld: 24, for a -64..320 height range). Each section is a
  ## fixed-shape PalettedContainer: 16x16x16 (4096 cells) for blocks,
  ## 4x4x4 (64 cells) for biomes, matching upstream's `BlockPalette`/
  ## `BiomePalette` type aliases.
  result = ChunkSections(count: count, minY: minY)
  result.blockSections = newSeq[PalettedContainer](count)
  result.biomeSections = newSeq[PalettedContainer](count)
  for i in 0 ..< count:
    result.blockSections[i] = newPalettedContainer(16, defaultBlock)
    result.biomeSections[i] = newPalettedContainer(4, defaultBiome)

proc sectionIndex*(s: ChunkSections, blockY: int32): int =
  ## Which section a world-space block Y coordinate falls in, relative to
  ## `minY`. Negative/out-of-range inputs are the caller's responsibility
  ## (upstream indexes an array too and would panic; this port doesn't add
  ## a bounds check upstream doesn't have).
  int((blockY - s.minY) div 16)

proc getBlock*(s: ChunkSections, x, y, z: int32): PaletteValue =
  let idx = sectionIndex(s, y)
  let localY = int(y - s.minY) mod 16
  get(s.blockSections[idx], int(x and 15), localY, int(z and 15))

proc setBlock*(s: var ChunkSections, x, y, z: int32, value: PaletteValue): PaletteValue =
  let idx = sectionIndex(s, y)
  let localY = int(y - s.minY) mod 16
  set(s.blockSections[idx], int(x and 15), localY, int(z and 15), value)
