## Exercises `/save-all`, `/list`, `/list uuids`, and `/kill` through real
## Tree/dispatch walks. Same caveat as every other file in this
## directory: check-verified, not runtime-proven (NIMONY-COMPILER-BUGS.md #1).

import std/[assertions, syncio]
import ../../command/cmdtree, ../../command/cmdsource, ../../command/cmddispatch
import ../entity/entity
import ../playerregistry
import ../../util/gamemode
import saveall, list, kill

var gSaveAllCalled = false

proc recordSaveAll() {.closure.} =
  gSaveAllCalled = true

block saveAllBlock:
  var t = newTree()
  registerSaveAll(t)
  let source = CommandSource(saveAllProc: recordSaveAll)
  let r = executeCommand(t, "save-all", source)
  assert r.isOk, "expected /save-all to succeed"
  assert gSaveAllCalled, "expected saveAllProc to be called"

  gSaveAllCalled = false
  let r2 = executeCommand(t, "save-all flush", source)
  assert r2.isOk, "expected /save-all flush to succeed"
  assert gSaveAllCalled, "expected saveAllProc to be called for the flush branch too"

proc makeTestPlayer(name, uuid: string): Player =
  let ent = newEntity(1'i32, uuid, EntityDimensions(width: 0.6'f32, height: 1.8'f32))
  let le = LivingEntity(entity: ent, health: 20.0'f32, maxHealth: 20.0'f32)
  Player(livingEntity: le, gameProfileName: name, gamemode: Survival)

block listEmptyBlock:
  var t = newTree()
  registerList(t)
  let source = CommandSource(playerRegistry: nil)
  let r = executeCommand(t, "list", source)
  assert r.isOk, "expected /list to succeed with no registry"
  assert r.value == 0'i32, "expected 0 players with a nil registry"

block listWithPlayersBlock:
  var t = newTree()
  registerList(t)
  let reg = newPlayerRegistry()
  addPlayer(reg, makeTestPlayer("Alice", "uuid-1"))
  addPlayer(reg, makeTestPlayer("Bob", "uuid-2"))
  let source = CommandSource(playerRegistry: reg)

  let r = executeCommand(t, "list", source)
  assert r.isOk, "expected /list to succeed"
  assert r.value == 2'i32, "expected 2 players listed"

  let rUuids = executeCommand(t, "list uuids", source)
  assert rUuids.isOk, "expected /list uuids to succeed"
  assert rUuids.value == 2'i32, "expected 2 players in the uuids form too"

block killNoPlayerBlock:
  var t = newTree()
  registerKill(t)
  let source = CommandSource()
  let r = executeCommand(t, "kill", source)
  assert not r.isOk, "expected /kill to fail with no player source"

block killSelfBlock:
  var t = newTree()
  registerKill(t)
  let p = makeTestPlayer("Carol", "uuid-3")
  let source = CommandSource(player: p)
  let r = executeCommand(t, "kill", source)
  assert r.isOk, "expected /kill to succeed"
  assert p.livingEntity.health == 0.0'f32, "expected health to be zeroed"
  let (removed, reason) = p.livingEntity.entity.removalReason
  assert removed, "expected removalReason to be set"
  assert reason == rrKilled, "expected removal reason to be rrKilled"

echo "save-all/list/kill command tests: all checks passed"
