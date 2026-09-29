## Exercises the registered `/gamemode` command through a real
## Tree/dispatch walk, not just a direct proc call - proves
## registerGamemode's node shape actually parses and executes.
##
## Like everything else that imports src/server/entity/entity.nim
## (directly or, as here, via cmdsource.nim's `player` field), this hits
## the closures-through-vtables runtime crash cataloged as bug #1 in
## NIMONY-COMPILER-BUGS.md - `nimony check` passes clean (verified), but
## `nimony c -r` does not run. Documented honestly, not claimed as
## runtime-proven.

import std/[assertions, syncio]
import ../../command/cmdtree, ../../command/cmdsource, ../../command/cmddispatch
import ../entity/entity
import ../../util/gamemode as gm
import gamemode

var t = newTree()
registerGamemode(t)

let ent = newEntity(1'i32, "test-uuid", EntityDimensions(width: 0.6'f32, height: 1.8'f32))
let living = LivingEntity(entity: ent, health: 20.0'f32, maxHealth: 20.0'f32)
let player = Player(livingEntity: living, gameProfileName: "tester", gamemode: Survival)

var messages: seq[string] = @[]
let source = CommandSource(
  sendMessageProc: proc(m: string) {.closure.} = messages.add(m),
  player: player,
)

let r1 = executeCommand(t, "gamemode creative", source)
assert r1.isOk, "expected /gamemode creative to succeed"
assert r1.value == 1'i32, "expected 1 target changed"
assert player.gamemode == Creative, "gamemode should now be creative"
assert messages.len == 1, "expected exactly one feedback message"

# No-op: already creative.
let r2 = executeCommand(t, "gamemode creative", source)
assert r2.isOk, "no-op should still be Ok"
assert r2.value == 0'i32, "no-op should report 0 succeeded"

# Bad literal shouldn't match the tree at all.
let r3 = executeCommand(t, "gamemode bogus", source)
assert not r3.isOk, "invalid gamemode name should fail to parse"

echo "gamemode command test: all checks passed"
