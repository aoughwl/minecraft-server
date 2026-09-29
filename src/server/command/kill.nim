## The `/kill` command.
## Port of upstream/pumpkin/src/command/commands/kill.rs
##
## Self-target form only (`/kill` with no arguments, killing the issuing
## player) - the `<targets>` multi-entity form needs
## `EntityArgumentType::Entities`, an entity-selector argument type not
## in `src/command/argtype.nim`'s `ArgValue` union yet (same blocker
## `gamemode.nim`'s doc comment already cites for its own `<target>`
## form). `target.kill(target.as_ref())` becomes a direct health-zero +
## removal-reason write on `LivingEntity`/`Entity` - no real
## `EntityBase.kill()` behaviour (death event, drops, XP) exists yet,
## same simplification level as `entity.nim`'s other TODO-marked
## behaviour hooks.
##
## Not ported: permission-registry registration and the translated
## `COMMANDS_KILL_SUCCESS_SINGLE`/`COMMANDS_KILL_SUCCESSFUL` feedback
## text (plain string instead, same simplification as the rest of this
## port).

import ../../command/cmdtree, ../../command/cmdsource, ../../command/cmderrors
import ../entity/entity

const
  KillDescription* = "Kills all target entities."
  KillPermission* = "minecraft:command.kill"

proc killSelfExecute(source: CommandSource, args: seq[ParsedArg]): CmdResult[int32] =
  let p = source.player
  if p == nil:
    return cmdErr[int32](cekExpectedSymbol, "No entity was found")
  p.livingEntity.health = 0.0'f32
  p.livingEntity.entity.removalReason = (true, rrKilled)
  sendMessage(source, "Killed " & p.gameProfileName)
  cmdOk[int32](1'i32)

proc registerKill*(t: var Tree) =
  ## Port of `register()`'s tree shape, minus the `<targets>` branch (see
  ## the file doc comment above).
  let cmdNode = addLiteral(t, RootIndex, "kill")
  setCommand(t, cmdNode, killSelfExecute)
