## Exercises `/stop` through a real Tree/dispatch walk. `stop.nim` doesn't
## import src/server/entity/entity.nim at all (unlike gamemode/say/me,
## which need `Player`), so this test is a rare case in src/server/command/
## that genuinely could run via `nimony c -r` if not for cmdsource.nim
## itself now importing entity.nim (for the `player` field) - so it still
## hits the same closures-through-vtables crash cataloged as bug #1 in
## NIMONY-COMPILER-BUGS.md, transitively, not directly. Check-verified,
## not runtime-proven.

import std/[assertions, syncio]
import ../../command/cmdtree, ../../command/cmdsource, ../../command/cmddispatch
import stop

var t = newTree()
registerStop(t)

var stopped = false
let source = CommandSource(
  stopProc: proc() {.closure.} = stopped = true,
)

let r = executeCommand(t, "stop", source)
assert r.isOk, "expected /stop to succeed"
assert r.value == 1'i32
assert stopped, "expected stopProc to have been called"

echo "stop command test: all checks passed"
