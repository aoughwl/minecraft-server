## Real behavior test for playerregistry.nim, run via `nimony c -r`.
## Imports entity.nim (for `Player`), so it's subject to the same
## closures-through-vtables crash documented in NIMONY-COMPILER-BUGS.md
## #1 - check-verified, not runtime-proven, same caveat as every other
## file that touches `Player`.

import std/[assertions, syncio]
import entity/entity
import ../util/gamemode
import playerregistry

proc mkPlayer(uuid, name: string): Player =
  let e = Entity(entityUuid: uuid)
  let le = LivingEntity(entity: e, health: 20.0'f32, maxHealth: 20.0'f32)
  Player(livingEntity: le, gameProfileName: name, gamemode: Survival)

let reg = newPlayerRegistry()
assert reg.allPlayers().len == 0

let alice = mkPlayer("uuid-1", "alice")
let bob = mkPlayer("uuid-2", "bob")
reg.addPlayer(alice)
reg.addPlayer(bob)
assert reg.allPlayers().len == 2

let foundByUuid = reg.findByUuid("uuid-2")
assert foundByUuid != nil
assert foundByUuid.gameProfileName == "bob"

let foundByName = reg.findByName("alice")
assert foundByName != nil
assert foundByName.livingEntity.entity.entityUuid == "uuid-1"

assert reg.findByUuid("no-such-uuid") == nil
assert reg.findByName("no-such-name") == nil

var messagesSent: seq[string] = @[]
proc collect(p: Player, message: string) {.closure.} =
  messagesSent.add(p.gameProfileName & ":" & message)

reg.broadcast(collect, "hello")
assert messagesSent.len == 2
assert messagesSent[0] == "alice:hello"
assert messagesSent[1] == "bob:hello"

reg.removePlayerByUuid("uuid-1")
assert reg.allPlayers().len == 1
assert reg.findByUuid("uuid-1") == nil
assert reg.findByUuid("uuid-2") != nil

echo "playerregistry: all checks passed"
