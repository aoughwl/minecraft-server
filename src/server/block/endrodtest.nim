## Real, run test for `end_rod.nim`'s `onPlaceEndRod` and
## `worldstub.nim`'s new `getNeighborBlockState`/`getBlockStateAt`.
## `nimony c -r` this directly (not through the vtable - see end_rod.nim's
## header for why).

import std/[assertions, syncio]
import end_rod
import blockbehaviour  # BlockDirection (bdUp)
import blockstateid
import ../world/worldstub
import ../../world/tick  # BlockPos, blockPos
import ../../world/palette  # PaletteValue

# --- getNeighborBlockState / getBlockStateAt ---------------------------

block:
  let w = newWorld()
  let base = blockPos(5'i32, 10'i32, 5'i32)
  setBlockState(w, blockPos(5'i32, 11'i32, 5'i32), 42'u32)  # base + up
  assert getNeighborBlockState(w, base, 0'i32, 1'i32, 0'i32) == 42'u32
  assert getBlockStateAt(w, 5'i32, 11'i32, 5'i32) == 42'u32
  # A direction that wasn't written reads air.
  assert getNeighborBlockState(w, base, 0'i32, -1'i32, 0'i32) == AirState
  echo "getNeighborBlockState/getBlockStateAt: OK"

# --- onPlaceEndRod: no neighbor end rod -> facing = opposite of placement
# direction (upstream's "nothing to align with" default) --------------

block:
  let w = newWorld()
  let pos = blockPos(0'i32, 0'i32, 0'i32)
  # Nothing placed at pos+up, so the neighbor is air, not an end rod.
  let stateId = onPlaceEndRod(w, pos, bdUp)
  let pr = statePropValues("end_rod", stateId)
  assert pr.ok
  var facing = ""
  for i in 0 ..< pr.values.len:
    if pr.values[i][0] == "facing": facing = pr.values[i][1]
  assert facing == "down", "expected opposite-of-up (down), got " & facing
  echo "onPlaceEndRod (no matching neighbor): OK, facing=" & facing

# --- onPlaceEndRod: neighbor end rod pointing back -> facing = placement
# direction itself (the "align with existing rod" branch) --------------

block:
  let w = newWorld()
  let pos = blockPos(0'i32, 0'i32, 0'i32)
  # Place a real end_rod state at pos+up, facing "down" (pointing back at
  # `pos`, i.e. opposite(bdUp)) - this should trigger the "align" branch.
  let neighborR = resolveStateId("end_rod", @[("facing", "down")])
  assert neighborR.ok
  setBlockState(w, blockPos(0'i32, 1'i32, 0'i32), PaletteValue(neighborR.stateId))
  let stateId = onPlaceEndRod(w, pos, bdUp)
  let pr = statePropValues("end_rod", stateId)
  assert pr.ok
  var facing = ""
  for i in 0 ..< pr.values.len:
    if pr.values[i][0] == "facing": facing = pr.values[i][1]
  assert facing == "up", "expected placement direction (up), got " & facing
  echo "onPlaceEndRod (matching neighbor): OK, facing=" & facing

echo "all end_rod / neighbor-lookup checks passed"
