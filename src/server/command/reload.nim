## The `/reload` command.
## Port of upstream/pumpkin/src/command/commands/reload.rs
##
## Not ported: permission-registry registration, and the translated
## `COMMANDS_RELOAD_SUCCESS` feedback text (plain string stands in, same
## simplification as the rest of this port). `reloadProc` stands in for
## `server.reload_datapacks(&server)` - no `Server`/datapack type exists
## in this port yet; `nil` is a safe no-op.

import ../../command/cmdtree, ../../command/cmdsource, ../../command/cmderrors

const
  ReloadDescription* = "Reloads the server's datapacks."
  ReloadPermission* = "minecraft:command.reload"

proc reloadExecute(source: CommandSource, args: seq[ParsedArg]): CmdResult[int32] =
  ## Upstream announces the reload before doing it, so feedback arrives
  ## even though reloading takes a moment.
  sendMessage(source, "Reloading datapacks...")
  if source.reloadProc != nil:
    source.reloadProc()
  cmdOk[int32](0'i32)

proc registerReload*(t: var Tree) =
  let cmdNode = addLiteral(t, RootIndex, "reload", executable = true)
  setCommand(t, cmdNode, reloadExecute)
