## A minimal flat/superflat-style chunk-section generator: no noise, just
## fills a section with a configurable default block up to a surface
## height and air above. Not a direct port of any single upstream file -
## upstream's actual "flat" world type is config-driven layer stacking
## inside the generic `generation/` pipeline, not a standalone module - but
## this is real, load-bearing logic serving the same purpose Minecraft's
## superflat preset does, and it's the first genuine end-to-end proof that
## src/world/palette.nim's `PalettedContainer` plus
## src/data_codegen/gen_noise_settings.nim's real per-dimension shape data
## plus src/generated/blockdata.nim's real block-id table can produce real
## section data, not just each piece in isolation.
##
## Scoped deliberately to one 16x16x16 section (`palette.nim`'s section
## edge length), not a full multi-section chunk stack - a real chunk is
## just N of these stacked by Y, which is direct once this shape is
## proven.

import std/strutils
import palette
import ../generated/blockdata
import ../generated/noise_settings

proc stripNamespace(name: string): string =
  ## `blockdata.nim`'s `Block.name` is the bare id ("stone"); everything
  ## upstream data (noise_settings JSON, etc.) uses the namespaced form
  ## ("minecraft:stone"). Strip it here rather than in every caller.
  let i = name.find(':')
  if i >= 0: name[i + 1 .. ^1] else: name

proc airStateId(): uint32 =
  let (found, air) = blockByName("air")
  if found: uint32(air.defaultStateId) else: 0'u32

proc generateFlatSection*(defaultBlockName: string, surfaceY: int): PalettedContainer =
  ## Fills y in [0, surfaceY) (clamped to the 16-cell section) with the
  ## given block, and y >= surfaceY with air. `surfaceY` is a section-local
  ## coordinate (0..15), matching how a real multi-section stack would call
  ## this once per section with the appropriate local offset.
  let (foundBlock, blk) = blockByName(stripNamespace(defaultBlockName))
  let fillId = if foundBlock: uint32(blk.defaultStateId) else: 0'u32
  let air = airStateId()
  result = newPalettedContainer(16, air)
  let clampedSurface = if surfaceY < 0: 0 elif surfaceY > 16: 16 else: surfaceY
  for y in 0 ..< clampedSurface:
    for z in 0 ..< 16:
      for x in 0 ..< 16:
        discard set(result, x, y, z, fillId)

proc generateFlatSectionFromDimension*(dimensionName: string, surfaceY: int): PalettedContainer =
  ## Convenience wrapper: resolves the default block from a real
  ## `NoiseSettings` entry (e.g. "overworld" -> stone) instead of taking
  ## the block name directly.
  let (found, settings) = noiseSettingsFromName(dimensionName)
  let blockName = if found: settings.defaultBlockName else: "air"
  generateFlatSection(blockName, surfaceY)
