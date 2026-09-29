## A minimal, honest placeholder for upstream's `World`/`Level` (world.rs/
## level.rs, ~18.7k lines combined - full server-authoritative world state:
## chunk loading/unloading, entity tracking, registries, networking
## broadcast, weather, time, etc).
##
## This is NOT that. It is JUST enough surface - block-state read/write over
## real chunk-section storage - to let `Player`/concrete items/blocks compile
## and be exercised in tests, the same placeholder-type pattern already
## established by `src/inventory/itemstub.nim` (a placeholder `Item`/
## `ItemStack`) and `src/server/entity/entity.nim`'s `DamageType`/`EntityKind`
## placeholders. Extend this only as concrete work actually needs more of
## it - resist building out `World` speculatively ahead of a real caller,
## per this repo's house style.
##
## Backed by `src/world/palette.nim`'s `PalettedContainer` (dim=16, the real
## block-section shape), keyed by chunk-section coordinate. No chunk
## loading/generation/persistence - sections are created on first write,
## default-filled with `AirState`, and never evicted.

import ../../world/palette
import ../../world/tick  # BlockPos

const
  SectionDim = 16'i32
  AirState*: PaletteValue = 0'u32
    ## Stands in for `pumpkin_data`'s real air block-state id (0 in every
    ## vanilla version so far, but this is a placeholder constant, not a
    ## verified registry lookup - see the module doc above).

type
  SectionCoord = tuple[sx, sy, sz: int32]

  ChunkSection = object
    blocks: PalettedContainer

  World* = ref object
    ## Single-world, single-dimension, in-memory-only. No chunk
    ## loading/unloading, no persistence (that's `src/world/anvilformat.nim`'s
    ## job once wired up), no entity tracking, no networking.
    sections: seq[(SectionCoord, ChunkSection)]

proc newWorld*(): World =
  World(sections: @[])

proc floorDiv(v, n: int32): int32 {.inline.} =
  var q = v div n
  if (v mod n) < 0:
    dec q
  q

proc floorMod(v, n: int32): int32 {.inline.} =
  var r = v mod n
  if r < 0:
    r += n
  r

proc toSectionCoord(pos: BlockPos): (SectionCoord, int, int, int) =
  ## Splits a block position into its containing section's coordinate plus
  ## the block's local x/y/z within that 16^3 section. Uses floor
  ## division/modulo so negative coordinates land in the correct section
  ## rather than off-by-one toward zero, the same trap
  ## `src/world/anvilformat.nim`'s region-index math was explicitly
  ## verified against.
  let sx = floorDiv(pos.x, SectionDim)
  let sy = floorDiv(pos.y, SectionDim)
  let sz = floorDiv(pos.z, SectionDim)
  let lx = floorMod(pos.x, SectionDim)
  let ly = floorMod(pos.y, SectionDim)
  let lz = floorMod(pos.z, SectionDim)
  ((sx: sx, sy: sy, sz: sz), int(lx), int(ly), int(lz))

proc sectionIndex(w: World, coord: SectionCoord): int =
  for i, (c, _) in w.sections:
    if c == coord:
      return i
  result = -1

proc getOrCreateSection(w: World, coord: SectionCoord): int =
  let i = sectionIndex(w, coord)
  if i >= 0:
    return i
  w.sections.add((coord, ChunkSection(blocks: newPalettedContainer(SectionDim, AirState))))
  w.sections.len - 1

proc getBlockState*(w: World, pos: BlockPos): PaletteValue =
  ## Port of the read half of upstream `World::get_block_state`/
  ## `ChunkData::get_block_state`, collapsed into one call since there's no
  ## separate chunk-loading step here. Un-created sections read as air.
  let (coord, lx, ly, lz) = toSectionCoord(pos)
  let i = sectionIndex(w, coord)
  if i < 0:
    return AirState
  w.sections[i][1].blocks.get(lx, ly, lz)

proc setBlockState*(w: World, pos: BlockPos, state: PaletteValue): PaletteValue {.discardable.} =
  ## Port of the write half of upstream `World::set_block_state`. Returns
  ## the previous state, matching `PalettedContainer.set`'s own contract.
  let (coord, lx, ly, lz) = toSectionCoord(pos)
  let i = getOrCreateSection(w, coord)
  result = w.sections[i][1].blocks.set(lx, ly, lz, state)

proc getBlockStateAt*(w: World, x, y, z: int32): PaletteValue {.inline.} =
  ## Same as `getBlockState`, but takes bare coordinates instead of a
  ## `BlockPos` - lets a caller resolve a neighbor position (`pos.x + dx`
  ## etc.) without this module needing to know about direction enums.
  ## Deliberately kept direction-agnostic: `BlockDirection` lives in
  ## `src/server/block/blockbehaviour.nim`, which imports `entity.nim` -
  ## importing it here would pull that dependency into every consumer of
  ## this module, including `worldstubtest.nim`, which is currently one of
  ## the few genuinely runtime-proven files in this port (no `entity.nim`
  ## in its import graph, so it isn't affected by the closures-through-
  ## vtables crash documented in NIMONY-COMPILER-BUGS.md #1). Callers that
  ## have a `BlockDirection` convert it to an offset themselves (see
  ## `directionOffset` in `src/server/block/blockbehaviour.nim`) and call
  ## this, or the `getNeighborBlockState` wrapper below.
  getBlockState(w, blockPos(x, y, z))

proc getNeighborBlockState*(w: World, pos: BlockPos, dx, dy, dz: int32): PaletteValue {.inline.} =
  ## Port of the read half of upstream's `world.get_block_state(&position.
  ## offset(direction))` pattern (e.g. `end_rod.rs`'s neighbor check,
  ## `spreading_snowy_block.rs`'s `SnowyBlock::get_state_for_neighbor_
  ## update`). Takes an already-resolved `(dx, dy, dz)` offset rather than
  ## a `BlockDirection` for the same reason `getBlockStateAt` does.
  getBlockStateAt(w, pos.x + dx, pos.y + dy, pos.z + dz)
