## The `/save-off` command.
## Port of upstream/pumpkin/src/command/commands/saveoff.rs
##
## Not ported: permission-registry registration, and the translated
## `COMMANDS_SAVE_ALREADYOFF`/`COMMANDS_SAVE_DISABLED` feedback text
## (plain strings stand in, same simplification as the rest of this
## port). `context.server().worlds` (upstream iterates every loaded
## world, disabling each) has no equivalent here yet - see
## `CommandSource.setSaveEnabledProc`'s doc comment in cmdsource.nim.

import ../../command/cmdtree, ../../command/cmdsource, ../../command/cmderrors

const
  SaveOffDescription* = "Disables automatic server saves."
  SaveOffPermission* = "minecraft:command.save-off"

proc saveOffExecute(source: CommandSource, args: seq[ParsedArg]): CmdResult[int32] =
  let anyDisabled = setSaveEnabled(source, false)
  if not anyDisabled:
    return cmdErr[int32](cekExpectedSymbol, "Automatic saving is already disabled")
  sendMessage(source, "Automatic saving is now disabled")
  cmdOk[int32](1'i32)

proc registerSaveOff*(t: var Tree) =
  let cmdNode = addLiteral(t, RootIndex, "save-off", executable = true)
  setCommand(t, cmdNode, saveOffExecute)
