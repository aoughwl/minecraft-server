## Exercises `/setidletimeout` through a real Tree/dispatch walk.
## Unlike gamemode.nim's test, this command doesn't touch
## src/server/entity/entity.nim - but `nimony c -r` still fails, hitting
## the same closures-through-vtables crash signature (NIMONY-COMPILER-BUGS.md
## #1: eraiser.nim/ParamsTagId, lambdalifting.nim/env.s). This confirms the
## crash isn't specific to entity.nim: src/command/cmdtree.nim's own
## Command/Requirement closure fields are enough on their own. `nimony
## check` is clean (verified); this file is check-verified only, same as
## every other command in this directory.

import std/[assertions, syncio]
import ../../command/cmdtree, ../../command/cmdsource, ../../command/cmddispatch
import setidletimeout

var t = newTree()
registerSetIdleTimeout(t)

var lastStored = -1'i32
var messages: seq[string] = @[]
let source = CommandSource(
  sendMessageProc: proc(m: string) {.closure.} = messages.add(m),
  idleTimeoutProc: proc(minutes: int32) {.closure.} = lastStored = minutes,
)

let r1 = executeCommand(t, "setidletimeout 20", source)
assert r1.isOk, "expected /setidletimeout 20 to succeed"
assert r1.value == 20'i32
assert lastStored == 20'i32
assert messages.len == 1

let r2 = executeCommand(t, "setidletimeout 0", source)
assert r2.isOk
assert r2.value == 0'i32
assert lastStored == 0'i32

let r3 = executeCommand(t, "setidletimeout -1", source)
assert not r3.isOk, "negative minutes should fail"

echo "setidletimeout command test: all checks passed"
