## Round-trip test for blockstateid.nim, actually run via `nimony c -r`
## (no `entity.nim` import - genuinely runtime-provable, unlike most of
## src/server/block/). Verifies real values against src/generated/
## blockprops.nim's oak_log/iron_chain entries (hand-checked against the
## real assets/blocks.json + assets/properties.json data in this file's
## own commit message / gen_blockprops.nim's doc comment).

import std/assertions
import std/syncio
import blockstateid
import blockbehaviour
import chain

# oak_log: firstStateId 139, defaultStateId 140, single "axis" property
# (values x/y/z). Default axis is "y" (offset 1 = defaultStateId - firstStateId).
block:
  let r = resolveStateId("oak_log", @[("axis", "x")])
  assert r.ok
  assert r.stateId == 139, "axis=x should be firstStateId + 0"

  let r2 = resolveStateId("oak_log", @[("axis", "y")])
  assert r2.ok
  assert r2.stateId == 140, "axis=y should be the default state"

  let r3 = resolveStateId("oak_log", @[("axis", "z")])
  assert r3.ok
  assert r3.stateId == 141, "axis=z should be firstStateId + 2"

  # Omitting the property falls back to the real default (axis=y).
  let r4 = resolveStateId("oak_log", @[])
  assert r4.ok
  assert r4.stateId == 140, "no axis specified should resolve to the default state"

  let (defOk, defId) = defaultStateId("oak_log")
  assert defOk and defId == 140

# Reverse direction: decode a state id back into property values.
block:
  let p = statePropValues("oak_log", 139)
  assert p.ok
  assert p.values.len == 1
  assert p.values[0] == ("axis", "x")

  let p2 = statePropValues("oak_log", 141)
  assert p2.ok
  assert p2.values[0] == ("axis", "z")

# Unknown block / out-of-range state id both fail cleanly.
block:
  let bad = resolveStateId("this_block_does_not_exist", @[])
  assert not bad.ok

  let badState = statePropValues("oak_log", -5)
  assert not badState.ok

# chain.nim's real proof case: iron_chain has TWO properties (axis,
# waterlogged) - a genuine multi-property permutation, not just the
# single-property oak_log case above.
block:
  registerChainBlock()
  let b = lookupBlock("minecraft:iron_chain")
  assert b != nil
  let stateId = b.onPlace(bdUp, false)
  let decoded = statePropValues("iron_chain", stateId)
  assert decoded.ok
  var axisVal = ""
  var waterVal = ""
  for i in 0 ..< decoded.values.len:
    let pair = decoded.values[i]
    if pair[0] == "axis": axisVal = pair[1]
    if pair[0] == "waterlogged": waterVal = pair[1]
  assert axisVal == "y", "bdUp should resolve to axis=y"
  assert waterVal == "false"

  let stateId2 = b.onPlace(bdEast, true)
  let decoded2 = statePropValues("iron_chain", stateId2)
  assert decoded2.ok
  var axisVal2 = ""
  var waterVal2 = ""
  for i in 0 ..< decoded2.values.len:
    let pair = decoded2.values[i]
    if pair[0] == "axis": axisVal2 = pair[1]
    if pair[0] == "waterlogged": waterVal2 = pair[1]
  assert axisVal2 == "x", "bdEast should resolve to axis=x"
  assert waterVal2 == "true"
  assert stateId2 != stateId, "different placement inputs must give different state ids"

echo "blockstateid: all checks passed"
