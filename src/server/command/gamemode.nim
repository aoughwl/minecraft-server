## The `/gamemode` command.
## Port of upstream/pumpkin/src/command/commands/gamemode.rs
##
## Scope: single-target form (`/gamemode <mode>`, sets the issuing
## player's own gamemode). The multi-target form (`/gamemode <mode>
## <target selector>`) needs `EntityArgumentType::Players` (an
## entity-selector argument, not yet in src/command/'s `ArgValue`
## union - see argtype.nim's doc comment) and a player registry to
## resolve selectors against, neither of which exist in this port yet;
## documented here as a TODO rather than forced.
##
## Also not ported: the permission-registry registration call
## (`registry.register_permission_or_panic`, needs the unported
## `pumpkin_util::permission` module), the translated feedback messages
## (`TextComponent::translate_cross`, needs the unported `text` module -
## plain strings stand in, same simplification `cmderrors.nim`/
## `cmdsource.nim` already use), and the "only send feedback if the
## target isn't the sender and `send_command_feedback` game rule is on"
## branch (needs `Server.level_info.game_rules`, not modeled yet).

import ../../command/cmdtree, ../../command/cmdsource, ../../command/argtype,
       ../../command/cmderrors, ../../command/gamemodearg, ../../command/cmddispatch
import ../../util/gamemode
import ../entity/entity

const
  GamemodeDescription* = "Change a player's gamemode."
  GamemodePermission* = "minecraft:command.gamemode"

proc gamemodeExecute(source: CommandSource, args: seq[ParsedArg]): CmdResult[int32] =
  let (foundArg, argVal) = findArgSeq(args, "gamemode")
  if not foundArg or argVal.kind != avkString:
    return cmdErr[int32](cekInvalidBool, "Missing or malformed 'gamemode' argument")
  let (parsedOk, mode) = parseGameMode(argVal.stringVal)
  if not parsedOk:
    return cmdErr[int32](cekInvalidBool, "Invalid game mode '" & argVal.stringVal & "'")

  let target = source.player
  if target == nil:
    sendError(source, "This command can only be run by a player without a target selector")
    return cmdErr[int32](cekExpectedSymbol, "requires a player source")

  if target.gamemode == mode:
    return cmdOk[int32](0'i32) ## upstream: no-op counts as 0 succeeded, not an error

  target.gamemode = mode
  sendMessage(source, "Set own game mode to " & $mode)
  cmdOk[int32](1'i32)

proc registerGamemode*(t: var Tree) =
  ## Port of `register()`'s tree shape, minus the dropped
  ## `<target>` branch (see file doc comment) and permission
  ## registration (no registry ported yet - `requirements` is left
  ## empty, matching how a node with no requirement always passes
  ## `meetsRequirements`).
  let cmdNode = addLiteral(t, RootIndex, "gamemode")
  let argNode = addArgument(t, cmdNode, "gamemode", newGameModeArgumentType())
  setCommand(t, argNode, gamemodeExecute)
