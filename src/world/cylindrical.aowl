## Chunk-loading view distance math: which chunk coordinates fall within a
## player's cylindrical view radius, and the load/unload diff between two
## view positions.
## Port of upstream/world/src/cylindrical_chunk_iterator.rs
##
## Upstream's `all_chunks_within`/`get_offsets` walks a precomputed LUT
## (`data::chunk_view_lut::CHUNK_VIEW_LUT`) generated at the upstream server's
## own build time for one specific reason: performance, not semantics. That
## LUT lives in the still-unported (1.5M-line, mostly-generated)
## `data` crate. Since `is_within_distance` is the actual source of
## truth for cylinder membership (the LUT is just a cache of its results),
## `allChunksWithin` here recomputes membership directly with a bounding
## nested loop instead of consulting a LUT - same results, no precomputed
## table dependency. Revisit with a real LUT once data lands and
## this becomes a hot path.

import std/assertions
import ../util/vector2

type
  Cylindrical* = object
    center*: Vector2[int32]
    viewDistance*: uint8 ## Must be >= 1; upstream enforces this via `NonZero<u8>`.

proc newCylindrical*(center: Vector2[int32], viewDistance: uint8): Cylindrical {.inline.} =
  assert viewDistance >= 1, "viewDistance must be non-zero"
  Cylindrical(center: center, viewDistance: viewDistance)

proc isWithinDistance*(c: Cylindrical, x, z: int32): bool =
  let vd = int64(c.viewDistance)
  if vd == 1:
    return false
  var dx = int64(abs(x - c.center.x)) - 2
  var dz = int64(abs(z - c.center.y)) - 2
  let relX = if dx > 0: dx else: 0
  let relZ = if dz > 0: dz else: 0
  let hypSqr = relX * relX + relZ * relZ
  hypSqr < vd * vd

proc allChunksWithin*(c: Cylindrical): seq[Vector2[int32]] =
  ## Bounding box is `center +/- (viewDistance + 2)` since `isWithinDistance`
  ## subtracts a 2-chunk margin before the distance check (matches
  ## upstream's own `bound = view_distance + 1` test invariant, widened by
  ## one to be safely inclusive of the margin).
  result = @[]
  let bound = int32(c.viewDistance) + 2
  var dz = -bound
  while dz <= bound:
    var dx = -bound
    while dx <= bound:
      let x = c.center.x + dx
      let z = c.center.y + dz
      if isWithinDistance(c, x, z):
        result.add(vec2[int32](x, z))
      dx += 1
    dz += 1

proc changedChunks*(oldC, newC: Cylindrical): (seq[Vector2[int32]], seq[Vector2[int32]]) =
  ## Returns (loading, unloading): chunks newly in range and chunks newly
  ## out of range when the view moves from `oldC` to `newC`.
  var loading: seq[Vector2[int32]] = @[]
  var unloading: seq[Vector2[int32]] = @[]
  for c in allChunksWithin(newC):
    if not isWithinDistance(oldC, c.x, c.y):
      loading.add(c)
  for c in allChunksWithin(oldC):
    if not isWithinDistance(newC, c.x, c.y):
      unloading.add(c)
  (loading, unloading)
