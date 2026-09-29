## The `/defaultgamemode` command.
## Port of upstream/pumpkin/src/command/commands/defaultgamemode.rs
##
## First command in this directory to need a real player registry
## (`server.get_all_players()`) rather than a single-field stand-in -
## wired to `src/server/playerregistry.nim` via `CommandSource.playerRegistry`
## and the new `forceGamemode` flag (standing in for
## `server.basic_config.force_gamemode`, no `BasicConfiguration` type
## threaded through yet).
##
## Not ported: permission-registry registration (needs the unported
## `pumpkin_util::permission` module, same simplification as every
## other file here), the translated feedback message
## (`TextComponent::translate_cross`, plain string instead), and
## storing the changed default (`server.defaultgamemode.lock()...` -
## `CommandSource` has no `Server` reference to persist it on, so this
## returns the parsed mode but doesn't stash it anywhere; a real
## `Server` type would need a `defaultGamemode` field for that, out of
## scope for this pass).

import ../../command/cmdtree, ../../command/cmdsource, ../../command/argtype,
       ../../command/cmderrors, ../../command/gamemodearg, ../../command/cmddispatch
import ../../util/gamemode
import ../entity/entity
import ../playerregistry

const
  DefaultGamemodeDescription* = "Change the default gamemode."
  DefaultGamemodePermission* = "minecraft:command.defaultgamemode"

proc defaultGamemodeExecute(source: CommandSource, args: seq[ParsedArg]): CmdResult[int32] =
  let (foundArg, argVal) = findArgSeq(args, "gamemode")
  if not foundArg or argVal.kind != avkString:
    return cmdErr[int32](cekInvalidBool, "Missing or malformed 'gamemode' argument")
  let (parsedOk, mode) = parseGameMode(argVal.stringVal)
  if not parsedOk:
    return cmdErr[int32](cekInvalidBool, "Invalid game mode '" & argVal.stringVal & "'")

  var successfulChanges: int32 = 0
  let registry = source.playerRegistry
  if source.forceGamemode and registry != nil:
    for p in registry.allPlayers():
      if p.gamemode != mode:
        p.gamemode = mode
        successfulChanges += 1

  sendMessage(source, "The default game mode is now " & $mode)
  cmdOk[int32](successfulChanges)

proc registerDefaultGamemode*(t: var Tree) =
  ## Port of `register()`'s tree shape, minus permission registration
  ## (no registry ported yet).
  let cmdNode = addLiteral(t, RootIndex, "defaultgamemode")
  let argNode = addArgument(t, cmdNode, "gamemode", newGameModeArgumentType())
  setCommand(t, argNode, defaultGamemodeExecute)
