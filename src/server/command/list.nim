## The `/list` command.
## Port of upstream/pumpkin/src/command/commands/list.rs
##
## First command in this file to actually READ `CommandSource.playerRegistry`
## rather than just mutate through it (defaultgamemode.nim iterates to
## write `gamemode`; this only reads names/uuids). `nil` registry reports
## zero players, matching `defaultgamemode.nim`'s nil-is-safe precedent.
##
## Not ported: permission-registry registration, the translated
## `COMMANDS_LIST_PLAYERS`/`COMMANDS_LIST_NAMEANDID` feedback text (plain
## strings/comma-joins instead, same simplification as the rest of this
## port), and the per-client-platform (`Java`/`Bedrock`) max-players split
## - `CommandSource.maxPlayersProc` doesn't distinguish, matching every
## other `Server`-config stand-in already added here.

import ../../command/cmdtree, ../../command/cmdsource, ../../command/cmderrors
import ../playerregistry
import ../entity/entity

const
  ListDescription* = "Print the list of online players."
  ListPermission* = "minecraft:command.list"

proc playerNames(registry: nil PlayerRegistry): seq[string] =
  result = @[]
  if registry != nil:
    for p in registry.allPlayers():
      result.add(p.gameProfileName)

proc joinComma(items: seq[string]): string =
  result = ""
  for i, s in items:
    if i > 0:
      result.add(", ")
    result.add(s)

proc listNamesExecute(source: CommandSource, args: seq[ParsedArg]): CmdResult[int32] =
  let names = playerNames(source.playerRegistry)
  let maxP = maxPlayers(source, names.len.int32)
  sendMessage(source, "There are " & $names.len & " of a max of " & $maxP &
    " players online: " & joinComma(names))
  cmdOk[int32](names.len.int32)

proc listUuidsExecute(source: CommandSource, args: seq[ParsedArg]): CmdResult[int32] =
  var entries: seq[string] = @[]
  let registry = source.playerRegistry
  if registry != nil:
    for p in registry.allPlayers():
      entries.add(p.gameProfileName & " (" & p.livingEntity.entity.entityUuid & ")")
  let maxP = maxPlayers(source, entries.len.int32)
  sendMessage(source, "There are " & $entries.len & " of a max of " & $maxP &
    " players online: " & joinComma(entries))
  cmdOk[int32](entries.len.int32)

proc registerList*(t: var Tree) =
  ## Port of `register()`'s tree shape: `.executes(Names)` on the command
  ## node itself, `.then(literal("uuids").executes(Uuids))` as a branch.
  let cmdNode = addLiteral(t, RootIndex, "list")
  setCommand(t, cmdNode, listNamesExecute)
  let uuidsNode = addLiteral(t, cmdNode, "uuids")
  setCommand(t, uuidsNode, listUuidsExecute)
