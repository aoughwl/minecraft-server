## Proof that the BlockBehaviour vtable + registration shape works:
## register both proof-case blocks, look them up by name, and (statically
## checked only - see the runtime-crash note below) exercise both
## vtable methods.
##
## KNOWN LIMITATION, not a bug in this file: closures flowing through a
## ref-object vtable crash Nimony's compiled binary at runtime
## (`eraiser.nim`/`ParamsTagId` assertion), confirmed independently twice
## already (src/command/'s dispatcher, src/server/entity/'s own test).
## This file is written to prove real behaviour once that's fixed, exactly
## like entitytest.nim - `nimony check` passes clean, `nimony c -r` is
## expected to hit the same crash. Do not "fix" this by weakening the test.

import std/syncio
import blockbehaviour
import structure_void
import slime
import ../entity/entity

proc check(cond: bool, msg: string) =
  if not cond:
    echo "FAIL: " & msg
    quit(1)

registerStructureVoid()
registerSlime()

let svBehaviour = lookupBlock("minecraft:structure_void")
let slimeBehaviour = lookupBlock("minecraft:slime_block")
let missing = lookupBlock("minecraft:does_not_exist")
check(missing == nil, "unregistered name should look up to nil")

# Exercise both vtable methods through a real Entity, proving the
# BlockBehaviour -> EntityBase -> Entity plumbing actually threads
# through correctly (this is the part that will crash at `c -r` time
# per the note above, until the compiler bug is fixed).
let dims = EntityDimensions(width: 0.6'f32, height: 1.8'f32, eyeHeight: 1.62'f32)
let e = newEntity(1, "00000000-0000-0000-0000-000000000001", dims)
let eb = entityBaseOf(e)

if svBehaviour != nil:
  e.velocity.y = -5.0
  onLandedUpon(svBehaviour, eb, 3.0)
  updateEntityMovementAfterFallOn(svBehaviour, eb)
  check(e.velocity.y == 0.0, "structure_void's default update should zero vertical velocity")
else:
  check(false, "structure_void should be registered")

if slimeBehaviour != nil:
  e.velocity.y = -5.0
  onLandedUpon(slimeBehaviour, eb, 3.0)
  updateEntityMovementAfterFallOn(slimeBehaviour, eb)
  check(e.velocity.y > 0.0, "slime's bounce should flip vertical velocity positive")
else:
  check(false, "slime_block should be registered")

echo "all block-registration/vtable checks passed"
