## The `/save-on` command.
## Port of upstream/pumpkin/src/command/commands/saveon.rs
##
## Not ported: permission-registry registration, and the translated
## `COMMANDS_SAVE_ALREADYON`/`COMMANDS_SAVE_ENABLED` feedback text
## (plain strings stand in). Same `worlds`-registry gap as
## `saveoff.nim` - see `CommandSource.setSaveEnabledProc`'s doc comment.

import ../../command/cmdtree, ../../command/cmdsource, ../../command/cmderrors

const
  SaveOnDescription* = "Enables automatic server saves."
  SaveOnPermission* = "minecraft:command.save-on"

proc saveOnExecute(source: CommandSource, args: seq[ParsedArg]): CmdResult[int32] =
  let anyEnabled = setSaveEnabled(source, true)
  if not anyEnabled:
    return cmdErr[int32](cekExpectedSymbol, "Automatic saving is already enabled")
  sendMessage(source, "Automatic saving is now enabled")
  cmdOk[int32](1'i32)

proc registerSaveOn*(t: var Tree) =
  let cmdNode = addLiteral(t, RootIndex, "save-on", executable = true)
  setCommand(t, cmdNode, saveOnExecute)
