## Exercises `/say` and `/me` through a real Tree/dispatch walk. Like
## everything importing src/server/entity/entity.nim (via cmdsource.nim's
## `player` field), this hits the closures-through-vtables runtime crash
## cataloged as bug #1 in NIMONY-COMPILER-BUGS.md - `nimony check` passes
## clean (verified), `nimony c -r` does not run. Check-verified, not
## runtime-proven, same as gamemodetest.nim.

import std/[assertions, syncio]
import ../../command/cmdtree, ../../command/cmdsource, ../../command/cmddispatch
import say, me

var t = newTree()
registerSay(t)
registerMe(t)

var broadcasts: seq[(string, string)] = @[]
let source = CommandSource(
  displayName: "tester",
  broadcastProc: proc(msg: string, sender: string) {.closure.} = broadcasts.add((msg, sender)),
)

let r1 = executeCommand(t, "say hello everyone", source)
assert r1.isOk, "expected /say to succeed"
assert r1.value == 1'i32
assert broadcasts.len == 1
assert broadcasts[0][0] == "hello everyone"
assert broadcasts[0][1] == "tester"

let r2 = executeCommand(t, "me waves at the server", source)
assert r2.isOk, "expected /me to succeed"
assert r2.value == 1'i32
assert broadcasts.len == 2
assert broadcasts[1][0] == "waves at the server"

echo "say/me command test: all checks passed"
