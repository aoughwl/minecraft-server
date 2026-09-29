## Proves blockbehaviour.nim's real-block-table wiring (findRealBlock,
## registerBlock's unresolved-registration tracking) resolves against
## src/generated/blockdata.nim's real data.
##
## NOT RUNTIME-VERIFIED: this file transitively imports ../entity/entity
## (via blockbehaviour.nim), which is enough on its own to trigger the
## known closures-through-vtables compiler crash at `nimony c -r` -
## confirmed independently 8x elsewhere in this port (see
## src/server/entity/README.md). `nimony check` passes clean and every
## assertion below was hand-verified against the real generated data
## (grepped src/generated/blockdata.nim directly for slime_block's and
## structure_void's actual field values before writing these asserts),
## but this file itself cannot currently be executed to confirm it.
## The item-side equivalent (src/inventory/itemwiringtest.nim) has no
## entity.nim dependency and IS runtime-verified - see that file.

import std/assertions
import blockbehaviour
import structure_void
import slime

let (foundSlime, slimeData) = findRealBlock("minecraft:slime_block")
assert foundSlime
assert slimeData.name == "slime_block"
assert slimeData.hardness == 0.0

let (foundVoid, voidData) = findRealBlock("minecraft:structure_void")
assert foundVoid
assert voidData.name == "structure_void"

let (foundBogus, _) = findRealBlock("minecraft:not_a_real_block")
assert not foundBogus

# Both real proof-case blocks register with names that DO resolve, so
# nothing should land in the unresolved list from their own registration.
registerSlime()
registerStructureVoid()
assert unresolvedBlockRegistrations().len == 0
