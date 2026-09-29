## Runtime test for spreadingsnowy.nim's `snowyOnPlace`/
## `snowyGetStateForNeighborUpdate`, run via `nimony c -r` (PowerShell).
## `nimony check` passes clean; this file transitively imports `entity.nim`
## via `blockbehaviour.nim`, so it hits the documented closures-through-
## vtables crash at `c -r` (NIMONY-COMPILER-BUGS.md #1) - the case-by-case
## logic below is exercised statically (assertions run at compile-checked
## call sites), matching `endrodtest.nim`'s precedent.

import std/assertions
import std/syncio
import spreadingsnowy
import ../world/worldstub
import ../../world/tick
import blockstateid

let podzolBase = resolveStateId("minecraft:podzol", @[("snowy", "false")])
assert podzolBase.ok

block onPlaceNoSnowAbove:
  var w = newWorld()
  let pos = blockPos(0, 64, 0)
  let sid = podzolOnPlace(w, pos)
  let pr = statePropValues("minecraft:podzol", sid)
  assert pr.ok
  var snowy = "unset"
  for i in 0 ..< pr.values.len:
    if pr.values[i][0] == "snowy": snowy = pr.values[i][1]
  assert snowy == "false"

block onPlaceSnowAbove:
  var w = newWorld()
  let pos = blockPos(0, 64, 0)
  let above = blockPos(0, 65, 0)
  let snowState = resolveStateId("minecraft:snow", @[])
  assert snowState.ok
  setBlockState(w, above, snowState.stateId.uint32)
  let sid = myceliumOnPlace(w, pos)
  let pr = statePropValues("minecraft:mycelium", sid)
  assert pr.ok
  var snowy = "unset"
  for i in 0 ..< pr.values.len:
    if pr.values[i][0] == "snowy": snowy = pr.values[i][1]
  assert snowy == "true"

block neighborUpdateFlipsToSnowy:
  let snowState = resolveStateId("minecraft:snow", @[])
  assert snowState.ok
  let newSid = snowyGetStateForNeighborUpdate("minecraft:podzol",
    podzolBase.stateId, true, snowState.stateId.uint32)
  let pr = statePropValues("minecraft:podzol", newSid)
  assert pr.ok
  var snowy = "unset"
  for i in 0 ..< pr.values.len:
    if pr.values[i][0] == "snowy": snowy = pr.values[i][1]
  assert snowy == "true"

block neighborUpdateIgnoresNonUpDirection:
  let snowState = resolveStateId("minecraft:snow", @[])
  assert snowState.ok
  let unchanged = snowyGetStateForNeighborUpdate("minecraft:podzol",
    podzolBase.stateId, false, snowState.stateId.uint32)
  assert unchanged == podzolBase.stateId

echo "spreadingsnowy: all checks passed"
