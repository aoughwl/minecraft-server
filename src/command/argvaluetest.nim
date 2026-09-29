## Exercises uuidarg.nim/gamemodearg.nim/identifierarg.nim, which wire into
## argtype.nim's `ArgumentType` manual vtable. `nimony check` passes clean
## (verified below is what the whole codebase already treats as "passes
## static checking"), but `nimony c -r` hits the closures-through-vtables
## runtime crash (`eraiser.nim`/`lambdalifting.nim`, confirmed 9x across
## this port now - see src/server/entity/README.md for the fullest
## writeup). `parseUuidString` itself (the actual UUID hex parser, no
## closures involved) IS separately runtime-verified in coordtest.nim's
## sibling checks... actually it is not, since importing uuidarg.nim here
## pulls in argtype.nim regardless of which proc is called. A truly
## closure-free re-export would need its own file; not done here to avoid
## scope creep beyond this pass's directive.

import std/[syncio, assertions]
import string_reader, uuidarg, gamemodearg, identifierarg

block uuidTests:
  var r1 = newStringReader("3d569d3a-93ef-44a0-9f1c-f69db9d37a56")
  let g1 = newUuidArgumentType().parseProc(r1)
  assert g1.isOk

  let (ok1, u1) = parseUuidString("3d569d3a-93ef-44a0-9f1c-f69db9d37a56")
  assert ok1
  assert u1.hi == 0x3d569d3a93ef44a0'u64
  assert u1.lo == 0x9f1cf69db9d37a56'u64

  let (ok2, _) = parseUuidString("not-a-uuid")
  assert not ok2
  echo "uuid: OK"

block gamemodeTests:
  var r1 = newStringReader("survival")
  let g1 = newGameModeArgumentType().parseProc(r1)
  assert g1.isOk
  assert g1.value.stringVal == "survival"

  var r2 = newStringReader("bogus")
  let g2 = newGameModeArgumentType().parseProc(r2)
  assert not g2.isOk
  echo "gamemode: OK"

block identifierTests:
  var r1 = newStringReader("foo")
  let i1 = newIdentifierArgumentType().parseProc(r1)
  assert i1.isOk
  assert i1.value.stringVal == "foo"

  var r2 = newStringReader("foo:bar")
  let i2 = newIdentifierArgumentType().parseProc(r2)
  assert i2.isOk
  assert i2.value.stringVal == "foo:bar"
  echo "identifier: OK"

echo "all argvalue tests passed (check-verified only, see file header)"
