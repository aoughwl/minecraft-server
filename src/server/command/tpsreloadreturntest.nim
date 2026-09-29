## Exercises `/tps`, `/reload`, `/return` through real Tree/dispatch walks.
## Same caveat as stoptest.nim: none of these three import
## src/server/entity/entity.nim directly, but src/command/cmdsource.nim
## now does (for the `player` field added by gamemode.nim), so this test
## transitively hits the closures-through-vtables crash cataloged as bug
## #1 in NIMONY-COMPILER-BUGS.md at `nimony c -r`. Check-verified, not
## runtime-proven.

import std/[assertions, syncio]
import ../../command/cmdtree, ../../command/cmdsource, ../../command/cmddispatch
import tps, reload, returncmd

block tpsBlock:
  var t = newTree()
  registerTps(t)
  let source = CommandSource(
    tpsProc: proc(): float64 {.closure.} = 19.98,
    msptProc: proc(): float64 {.closure.} = 12.3,
  )
  let r = executeCommand(t, "tps", source)
  assert r.isOk, "expected /tps to succeed"

block reloadBlock:
  var t = newTree()
  registerReload(t)
  var reloaded = false
  let source = CommandSource(
    reloadProc: proc() {.closure.} = reloaded = true,
  )
  let r = executeCommand(t, "reload", source)
  assert r.isOk, "expected /reload to succeed"
  assert reloaded, "expected reloadProc to have been called"

block returnValueBlock:
  var t = newTree()
  registerReturn(t)
  let source = CommandSource()
  let r = executeCommand(t, "return 42", source)
  assert r.isOk, "expected 'return 42' to succeed"
  assert r.value == 42'i32, "expected the return value to be echoed back"

block returnFailBlock:
  var t = newTree()
  registerReturn(t)
  let source = CommandSource()
  let r = executeCommand(t, "return fail", source)
  assert r.isOk, "expected 'return fail' to succeed"
  assert r.value == 0'i32

echo "tps/reload/return command tests: all checks passed"
