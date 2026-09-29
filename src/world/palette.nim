## Chunk-section paletted storage: the compact block/biome array format
## Minecraft uses per 16x16x16 section (blocks) or 4x4x4 (biomes).
## Port of upstream/pumpkin-world/src/chunk/palette.rs's `HeterogeneousPaletteData`.
##
## Design decisions made porting this (flagged by an earlier pass as
## deserving one, rather than a rushed line-by-line translation):
## - Upstream is generic over `const DIM: usize` (16 for block sections, 4
##   for biome sections) via `[[[V; DIM]; DIM]; DIM]`. Nimony has no
##   const-generic array types, and forcing generality here buys nothing -
##   Minecraft only ever uses two concrete section shapes. So `dim` is a
##   plain `int` field set at construction, and storage is a flat seq of
##   length `dim*dim*dim` indexed by `(y*dim + z)*dim + x`, rather than
##   upstream's nested fixed arrays - same access pattern, no fixed-size-
##   array machinery needed.
## - Upstream is also generic over `V: Hash + Eq + Copy` (a block-state id
##   or biome id). Making the stored value type generic here hit real
##   Nimony friction (constrained generics need an explicit concept, and
##   plain `[V]` on an object type didn't resolve `==`/`HasDefault` against
##   an unconstrained `V`). Since both real uses (block-state id, biome id)
##   are plain integers, this follows the same "fixed concrete size over
##   forced generality" call already made for `dim`: the stored value type
##   is a concrete `uint32`, wide enough for either id space.
## - Left OUT for now: the Bedrock-specific `bedrock_palette_bits`/
##   `bedrock_water_state`/`has_random_ticking_fluid` helpers (need
##   `pumpkin_data::{BlockState, Fluid}`, not ported) and the on-disk
##   bit-packed (de)serialization (`ChunkSectionBlockStates`/
##   `ChunkSectionBiomes` codec, `format/anvil.rs`/`format/linear.rs`,
##   ~3.5k lines combined) - this file is the in-memory data structure
##   only, which is the part worth a deliberate design pass; the wire
##   format is a separate, mechanical follow-up once this shape is settled.

type
  PaletteValue* = uint32
    ## Wide enough for either a block-state id or a biome id.

  PaletteStorageKind = enum
    pskDense   ## One value per cell - used once the palette gets large.
    pskIndexed ## One palette-index byte per cell - the common case.

  PalettedContainer* = object
    dim: int                     ## Section edge length (16 for blocks, 4 for biomes).
    kind: PaletteStorageKind
    dense: seq[PaletteValue]     ## len == dim^3, valid when kind == pskDense.
    indices: seq[uint8]          ## len == dim^3, valid when kind == pskIndexed.
    palette: seq[PaletteValue]
    counts: seq[uint16]

proc idx(dim, x, y, z: int): int {.inline.} =
  (y * dim + z) * dim + x

proc newPalettedContainer*(dim: int, default: PaletteValue): PalettedContainer =
  let n = dim * dim * dim
  result = PalettedContainer(
    dim: dim,
    kind: pskIndexed,
    dense: @[],
    indices: newSeq[uint8](n),
    palette: @[default],
    counts: newSeq[uint16](1),
  )
  result.counts[0] = uint16(n)

proc paletteIndexOf(p: PalettedContainer, value: PaletteValue): int =
  for i, v in p.palette:
    if v == value:
      return i
  result = -1

proc get*(p: PalettedContainer, x, y, z: int): PaletteValue =
  let i = idx(p.dim, x, y, z)
  case p.kind
  of pskDense: p.dense[i]
  of pskIndexed: p.palette[p.indices[i]]

proc upgradeToDense(p: var PalettedContainer) =
  var dense = newSeq[PaletteValue](p.dim * p.dim * p.dim)
  for i in 0 ..< dense.len:
    dense[i] = p.palette[p.indices[i]]
  p.dense = dense
  p.indices = @[]
  p.kind = pskDense

proc set*(p: var PalettedContainer, x, y, z: int, value: PaletteValue): PaletteValue =
  ## Sets the cell and returns the previous value, mirroring upstream's
  ## `set`'s return of the original.
  let i = idx(p.dim, x, y, z)
  let original = p.get(x, y, z)
  if original == value:
    return original

  # Upstream tracks palette/counts bookkeeping regardless of storage kind -
  # Dense only skips the per-cell index array, not the palette occupancy
  # counting (a first pass here wrongly special-cased Dense to skip this,
  # which silently stopped the palette from ever shrinking back down once
  # upgraded - caught by palettetest.nim, not by "it compiles").
  let originalIndex = paletteIndexOf(p, original)

  var newIndex = paletteIndexOf(p, value)
  if newIndex < 0:
    p.palette.add(value)
    p.counts.add(0'u16)
    newIndex = p.palette.len - 1
  inc p.counts[newIndex]

  case p.kind
  of pskDense:
    p.dense[i] = value
  of pskIndexed:
    if newIndex <= 255:
      p.indices[i] = uint8(newIndex)
    else:
      upgradeToDense(p)
      p.dense[i] = value

  if originalIndex >= 0:
    dec p.counts[originalIndex]
    if p.counts[originalIndex] == 0:
      let lastIndex = p.palette.len - 1
      let lastValue = p.palette[lastIndex]
      let lastCount = p.counts[lastIndex]
      p.palette[originalIndex] = lastValue
      p.counts[originalIndex] = lastCount
      var newPalette = newSeq[PaletteValue](lastIndex)
      var newCounts = newSeq[uint16](lastIndex)
      for k in 0 ..< lastIndex:
        newPalette[k] = p.palette[k]
        newCounts[k] = p.counts[k]
      p.palette = newPalette
      p.counts = newCounts
      if p.kind == pskIndexed:
        for k in 0 ..< p.indices.len:
          if int(p.indices[k]) == lastIndex:
            p.indices[k] = uint8(originalIndex)

  result = original

proc paletteSize*(p: PalettedContainer): int {.inline.} =
  p.palette.len

proc isSingleValued*(p: PalettedContainer): bool {.inline.} =
  ## True when every cell holds the same value - the common case for a
  ## freshly generated all-air/all-stone section, worth a fast path when
  ## serializing (upstream's own palette format has a dedicated single-value
  ## encoding for exactly this).
  p.palette.len == 1
