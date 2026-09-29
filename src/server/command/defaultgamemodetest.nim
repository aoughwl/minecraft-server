## Exercises `/defaultgamemode` through a real Tree/dispatch walk,
## driving `CommandSource.playerRegistry`/`forceGamemode` end to end.
## Same caveat as every other file in this directory: check-verified,
## not runtime-proven (NIMONY-COMPILER-BUGS.md #1) - this file imports
## `entity.nim` transitively via `cmdsource.nim`.

import std/[assertions, syncio]
import ../../command/cmdtree, ../../command/cmdsource, ../../command/cmddispatch
import ../../util/gamemode
import ../entity/entity
import ../playerregistry
import defaultgamemode

proc mkPlayer(uuid, name: string; mode: GameMode): Player =
  let e = Entity(entityUuid: uuid)
  let le = LivingEntity(entity: e, health: 20.0'f32, maxHealth: 20.0'f32)
  Player(livingEntity: le, gameProfileName: name, gamemode: mode)

block forceChangesAllPlayers:
  var t = newTree()
  registerDefaultGamemode(t)
  let reg = newPlayerRegistry()
  reg.addPlayer(mkPlayer("u1", "alice", Survival))
  reg.addPlayer(mkPlayer("u2", "bob", Survival))
  reg.addPlayer(mkPlayer("u3", "carol", Creative)) ## already matches, no change
  let source = CommandSource(
    playerRegistry: reg,
    forceGamemode: true,
  )
  let r = executeCommand(t, "defaultgamemode creative", source)
  assert r.isOk, "expected /defaultgamemode creative to succeed"
  assert r.value == 2'i32, "expected 2 players actually changed"
  for p in reg.allPlayers():
    assert p.gamemode == Creative, "expected every player switched to Creative"

block noForceLeavesPlayersAlone:
  var t = newTree()
  registerDefaultGamemode(t)
  let reg = newPlayerRegistry()
  reg.addPlayer(mkPlayer("u1", "alice", Survival))
  let source = CommandSource(
    playerRegistry: reg,
    forceGamemode: false,
  )
  let r = executeCommand(t, "defaultgamemode creative", source)
  assert r.isOk, "expected /defaultgamemode creative to succeed even without force"
  assert r.value == 0'i32, "expected 0 changes when force_gamemode is off"
  assert reg.allPlayers()[0].gamemode == Survival, "expected alice untouched"

block noRegistryIsSafe:
  var t = newTree()
  registerDefaultGamemode(t)
  let source = CommandSource(forceGamemode: true) ## playerRegistry stays nil
  let r = executeCommand(t, "defaultgamemode creative", source)
  assert r.isOk, "expected /defaultgamemode creative to succeed with no registry"
  assert r.value == 0'i32, "expected 0 changes when there's no registry to iterate"

block invalidModeRejected:
  var t = newTree()
  registerDefaultGamemode(t)
  let source = CommandSource()
  let r = executeCommand(t, "defaultgamemode nonsense", source)
  assert not r.isOk, "expected /defaultgamemode nonsense to fail to parse"

echo "defaultgamemode command tests: all checks passed"
