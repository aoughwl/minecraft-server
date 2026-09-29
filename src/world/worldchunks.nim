## A minimal "which chunk columns are loaded, how do I look one up"
## registry, built on `chunkdata.nim`'s real `ChunkSections` (the full
## vertical-column block/biome storage) - the multi-chunk upgrade
## `src/server/world/worldstub.nim`'s doc comment flagged as a possible
## next step, following `src/server/playerregistry.nim`'s "minimal but
## real, seq-backed, no fake networking" precedent.
##
## Deliberately additive, not a replacement for `worldstub.nim`: that
## module's `World`/`getBlockState`/`setBlockState` already work and
## have consumers across src/server/block/, src/server/item/, and
## src/command/ - rewriting its API under single-threaded constraints
## without the parallel review this port's other risky changes get
## would be irresponsible. This lives in `src/world/` (general
## world-data-model utilities, alongside `palette.nim`/`chunkdata.nim`
## themselves) as a standalone piece a future pass can wire into
## `worldstub.nim` (or a real `World`/`Level` type) once there's a
## concrete reason to - e.g. an actual multi-chunk consumer.
##
## No chunk loading/generation/persistence (same scope line
## `worldstub.nim` draws): a column is "loaded" once `loadChunk` is
## called for it and stays loaded (default-air-filled) until
## `unloadChunk` removes it.

import chunkdata, palette

type
  ChunkPos* = tuple[cx, cz: int32]
    ## Chunk-column coordinate (16x16 blocks wide, full world height) -
    ## NOT the same granularity as `worldstub.nim`'s `SectionCoord`
    ## (16^3 cube), one level up.

  WorldChunks* = ref object
    columns: seq[(ChunkPos, ChunkSections)]
    sectionCount: int
    minY: int32
    defaultBlock: PaletteValue
    defaultBiome: PaletteValue

proc newWorldChunks*(sectionCount: int, minY: int32,
                      defaultBlock, defaultBiome: PaletteValue): WorldChunks =
  WorldChunks(columns: @[], sectionCount: sectionCount, minY: minY,
    defaultBlock: defaultBlock, defaultBiome: defaultBiome)

proc columnIndex(w: WorldChunks, pos: ChunkPos): int =
  for i, (c, _) in w.columns:
    if c == pos:
      return i
  result = -1

proc isChunkLoaded*(w: WorldChunks, pos: ChunkPos): bool =
  columnIndex(w, pos) >= 0

proc loadedChunkCount*(w: WorldChunks): int {.inline.} =
  w.columns.len

proc loadChunk*(w: WorldChunks, pos: ChunkPos): int {.discardable.} =
  ## Returns the column's index into `w.columns`. A no-op (returns the
  ## existing index) if `pos` is already loaded - "load" here is purely
  ## an in-memory presence flag, there's no generation/disk-read behind
  ## it yet (see file doc comment).
  let i = columnIndex(w, pos)
  if i >= 0:
    return i
  w.columns.add((pos, newChunkSections(w.sectionCount, w.minY, w.defaultBlock, w.defaultBiome)))
  w.columns.len - 1

proc unloadChunk*(w: WorldChunks, pos: ChunkPos): bool {.discardable.} =
  ## Returns whether a column was actually present to remove.
  let i = columnIndex(w, pos)
  if i < 0:
    return false
  w.columns.delete(i)
  true

proc chunkPosOf(x, z: int32): ChunkPos {.inline.} =
  ## Floor-division into 16-wide columns - the same negative-coordinate
  ## trap `src/server/world/worldstub.nim`'s `toSectionCoord`/
  ## `src/world/anvilformat.nim`'s region-index math were explicitly
  ## verified against.
  var cx = x shr 4
  var cz = z shr 4
  ## Arithmetic shift-right already floors for two's-complement negative
  ## integers in Nimony/C, so no extra correction is needed here (unlike
  ## `div`, which truncates toward zero) - verified by the round-trip
  ## test in worldchunkstest.nim rather than assumed.
  (cx: cx, cz: cz)

proc getBlockState*(w: WorldChunks, x, y, z: int32): PaletteValue =
  ## Reads a block, auto-loading the containing column first (matching
  ## `worldstub.nim`'s `getBlockState`'s "un-created reads as default"
  ## spirit, but here the column itself is created on read too, since
  ## `loadChunk` is meant to be an explicit tracked operation - callers
  ## that care about the loaded/unloaded distinction should call
  ## `isChunkLoaded`/`loadChunk` themselves first).
  let pos = chunkPosOf(x, z)
  let i = loadChunk(w, pos)
  let lx = x and 15
  let lz = z and 15
  getBlock(w.columns[i][1], lx, y, lz)

proc setBlockState*(w: WorldChunks, x, y, z: int32, value: PaletteValue): PaletteValue {.discardable.} =
  let pos = chunkPosOf(x, z)
  let i = loadChunk(w, pos)
  let lx = x and 15
  let lz = z and 15
  result = setBlock(w.columns[i][1], lx, y, lz, value)
