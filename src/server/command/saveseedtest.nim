## Exercises `/save-off`, `/save-on`, `/seed` through real Tree/dispatch
## walks. Same caveat as tpsreloadreturntest.nim: cmdsource.nim
## transitively imports src/server/entity/entity.nim, so this hits the
## closures-through-vtables crash cataloged as bug #1 in
## NIMONY-COMPILER-BUGS.md at `nimony c -r`. Check-verified, not
## runtime-proven.

import std/[assertions, syncio]
import ../../command/cmdtree, ../../command/cmdsource, ../../command/cmddispatch
import saveoff, saveon, seed

block saveOffBlock:
  var t = newTree()
  registerSaveOff(t)
  var enabled = true
  let source = CommandSource(
    setSaveEnabledProc: proc(e: bool): bool {.closure.} =
      if enabled != e:
        enabled = e
        return true
      return false,
  )
  let r = executeCommand(t, "save-off", source)
  assert r.isOk, "expected /save-off to succeed"
  assert not enabled, "expected saving to be disabled"

  # A second /save-off with saving already off should fail.
  let r2 = executeCommand(t, "save-off", source)
  assert not r2.isOk, "expected a repeat /save-off to report already-off"

block saveOnBlock:
  var t = newTree()
  registerSaveOn(t)
  var enabled = false
  let source = CommandSource(
    setSaveEnabledProc: proc(e: bool): bool {.closure.} =
      if enabled != e:
        enabled = e
        return true
      return false,
  )
  let r = executeCommand(t, "save-on", source)
  assert r.isOk, "expected /save-on to succeed"
  assert enabled, "expected saving to be enabled"

block seedBlock:
  var t = newTree()
  registerSeed(t)
  let source = CommandSource(
    getSeedProc: proc(): int64 {.closure.} = 123456789'i64,
  )
  let r = executeCommand(t, "seed", source)
  assert r.isOk, "expected /seed to succeed"
  assert r.value == 123456789'i32, "expected the seed to be echoed back as i32"

echo "save-off/save-on/seed command tests: all checks passed"
