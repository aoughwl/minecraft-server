## The `/tps` command.
## Port of upstream/pumpkin/src/command/commands/tps.rs
##
## Not ported: permission-registry registration, and the translated/colored
## feedback text (`TextComponent`/`NamedColor`, needs the unported
## `text`/`translation` modules - plain string stands in, same
## simplification the rest of this port uses). `tpsProc`/`msptProc` stand
## in for `context.source.server()`'s `get_tps`/`get_mspt`/`basic_config`
## - no `Server` type exists in this port yet; `nil` falls back to
## reporting 0.0, which is enough to prove the argument-free dispatch path
## without a fake tick-loop.

import ../../command/cmdtree, ../../command/cmdsource, ../../command/cmderrors

const
  TpsDescription* = "Displays the server TPS and MSPT."
  TpsPermission* = "minecraft:command.tps"

proc tpsExecute(source: CommandSource, args: seq[ParsedArg]): CmdResult[int32] =
  let tps = (if source.tpsProc != nil: source.tpsProc() else: 0.0)
  let mspt = (if source.msptProc != nil: source.msptProc() else: 0.0)
  sendMessage(source, "TPS: " & $tps & " MSPT: " & $mspt & "ms")
  cmdOk[int32](int32(tps))

proc registerTps*(t: var Tree) =
  let cmdNode = addLiteral(t, RootIndex, "tps", executable = true)
  setCommand(t, cmdNode, tpsExecute)
