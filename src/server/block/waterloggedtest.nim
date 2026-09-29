## Round-trip test for barrier.nim/mangroveroots.nim's state-id math -
## single-property (waterlogged-only) blocks, the simplest possible case
## on top of blockstateid.nim's resolution API. Like every other file in
## this directory, this transitively imports entity.nim (via
## blockbehaviour.nim), so it hits the documented closures-through-vtables
## runtime crash (NIMONY-COMPILER-BUGS.md #1) at `nimony c -r` - check-
## verified only, same caveat as the rest of src/server/block/.

import std/assertions
import std/syncio
import blockstateid
import blockbehaviour
import barrier
import mangroveroots

block:
  registerBarrierBlock()
  let b = lookupBlock("barrier")
  assert b != nil

  let sDry = b.onPlace(bdUp, false)
  let dDry = statePropValues("barrier", sDry)
  assert dDry.ok and dDry.values[0] == ("waterlogged", "false")

  let sWet = b.onPlace(bdUp, true)
  let dWet = statePropValues("barrier", sWet)
  assert dWet.ok and dWet.values[0] == ("waterlogged", "true")

  assert sDry != sWet, "waterlogged and dry barrier must be distinct states"
  echo "barrier state ids: dry=", $sDry, " wet=", $sWet

block:
  registerMangroveRootsBlock()
  let b = lookupBlock("mangrove_roots")
  assert b != nil

  let sDry = b.onPlace(bdUp, false)
  let dDry = statePropValues("mangrove_roots", sDry)
  assert dDry.ok and dDry.values[0] == ("waterlogged", "false")

  let sWet = b.onPlace(bdUp, true)
  let dWet = statePropValues("mangrove_roots", sWet)
  assert dWet.ok and dWet.values[0] == ("waterlogged", "true")

  assert sDry != sWet, "waterlogged and dry mangrove_roots must be distinct states"
  echo "mangrove_roots state ids: dry=", $sDry, " wet=", $sWet

echo "waterlogged block checks passed"
