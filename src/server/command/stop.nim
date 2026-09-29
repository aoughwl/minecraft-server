## The `/stop` command.
## Port of upstream/pumpkin/src/command/commands/stop.rs
##
## Not ported: permission-registry registration, and the translated
## `COMMANDS_STOP_STOPPING`/`COMMANDS_STOP_START` feedback text with its
## red coloring (needs the unported `text`/`translation` modules - plain
## string stands in, same simplification as the rest of this port).

import ../../command/cmdtree, ../../command/cmdsource, ../../command/cmderrors

const
  StopDescription* = "Stop the server."
  StopPermission* = "minecraft:command.stop"

proc stopExecute(source: CommandSource, args: seq[ParsedArg]): CmdResult[int32] =
  sendMessage(source, "Stopping the server")
  stopServer(source)
  cmdOk[int32](1'i32)

proc registerStop*(t: var Tree) =
  let cmdNode = addLiteral(t, RootIndex, "stop", executable = true)
  setCommand(t, cmdNode, stopExecute)
