## Round-trip test for logs.nim/glazed_terracotta.nim's state-id math,
## following blockstateidtest.nim's pattern. Like every other file in
## this directory, this transitively imports entity.nim (via
## blockbehaviour.nim), so it hits the documented closures-through-vtables
## runtime crash (NIMONY-COMPILER-BUGS.md #1) at `nimony c -r` - check-
## verified only, same caveat as the rest of src/server/block/.

import std/assertions
import std/syncio
import blockstateid
import blockbehaviour
import logs
import glazed_terracotta

# logs.nim: oak_log, single "axis" property, direction -> axis mapping.
block:
  registerLogBlock()
  let b = lookupBlock("oak_log")
  assert b != nil

  let sUp = b.onPlace(bdUp, false)
  let dUp = statePropValues("oak_log", sUp)
  assert dUp.ok and dUp.values[0] == ("axis", "y")

  let sEast = b.onPlace(bdEast, false)
  let dEast = statePropValues("oak_log", sEast)
  assert dEast.ok and dEast.values[0] == ("axis", "x")

  let sNorth = b.onPlace(bdNorth, false)
  let dNorth = statePropValues("oak_log", sNorth)
  assert dNorth.ok and dNorth.values[0] == ("axis", "z")

  assert sUp != sEast and sEast != sNorth and sUp != sNorth,
    "three different placement directions must give three different state ids"

# glazed_terracotta.nim: white_glazed_terracotta, single "facing" property.
# onPlaceImpl falls back to defaultOnPlace (no player reference through
# the narrower vtable interface) - onPlaceGlazedTerracotta (the real,
# player-facing-aware path) is exercised directly instead.
block:
  registerGlazedTerracottaBlock()
  let b = lookupBlock("white_glazed_terracotta")
  assert b != nil

  let viaVtable = b.onPlace(bdNorth, false)
  let (defOk, defId) = defaultStateId("white_glazed_terracotta")
  assert defOk
  assert viaVtable == defId, "vtable path has no player, must fall back to the default state"

  # Direct call with a nil player also falls back to the default.
  let viaNilPlayer = onPlaceGlazedTerracotta(nil)
  assert viaNilPlayer == defId

echo "logs/glazed_terracotta: all checks passed"
