## Exercises `/difficulty` (query and all 4 set forms) through real
## Tree/dispatch walks. Same caveat as tpsreloadreturntest.nim: check-
## verified, not runtime-proven (NIMONY-COMPILER-BUGS.md #1).

import std/[assertions, syncio]
import ../../command/cmdtree, ../../command/cmdsource, ../../command/cmddispatch
import ../../util/difficulty
import difficulty as difficultycmd

block queryBlock:
  var t = newTree()
  registerDifficulty(t)
  let source = CommandSource(
    difficultyProc: proc(): Difficulty {.closure.} = Hard,
  )
  let r = executeCommand(t, "difficulty", source)
  assert r.isOk, "expected /difficulty query to succeed"
  assert r.value == ord(Hard).int32

var gCalledWith = Peaceful
var gWasCalled = false

proc recordSetDifficulty(d: Difficulty) {.closure.} =
  gWasCalled = true
  gCalledWith = d

block setBlock:
  var t = newTree()
  registerDifficulty(t)
  let source = CommandSource(
    difficultyProc: proc(): Difficulty {.closure.} = Peaceful,
    setDifficultyProc: recordSetDifficulty,
  )
  let r = executeCommand(t, "difficulty hard", source)
  assert r.isOk, "expected /difficulty hard to succeed"
  assert gWasCalled, "expected setDifficultyProc to be called"
  assert gCalledWith == Hard, "expected setDifficultyProc to be called with Hard"

block alreadySetBlock:
  var t = newTree()
  registerDifficulty(t)
  let source = CommandSource(
    difficultyProc: proc(): Difficulty {.closure.} = Normal,
  )
  let r = executeCommand(t, "difficulty normal", source)
  assert not r.isOk, "expected /difficulty normal to fail when already normal"

echo "difficulty command tests: all checks passed"
