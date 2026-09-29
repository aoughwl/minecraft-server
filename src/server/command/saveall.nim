## The `/save-all` command.
## Port of upstream/pumpkin/src/command/commands/saveall.rs
##
## Not ported: permission-registry registration, the translated
## `COMMANDS_SAVE_SAVING`/`COMMANDS_SAVE_SUCCESS`/`COMMANDS_SAVE_FAILED`
## feedback text (plain strings, same simplification as the rest of
## this port), and the async `server.save_all()` task-spawn (no
## concurrency model exists in this port yet - `saveAllProc` is called
## synchronously and assumed to succeed, matching `stopProc`'s spirit).
## The `save-all flush` sub-literal (upstream registers the same
## executor under both `save-all` and `save-all flush`) is kept as a
## real second node rather than collapsed away, since that's exactly
## what upstream's tree shape does.

import ../../command/cmdtree, ../../command/cmdsource, ../../command/cmderrors

const
  SaveAllDescription* = "Saves the server to disk."
  SaveAllPermission* = "minecraft:command.save-all"

proc saveAllExecute(source: CommandSource, args: seq[ParsedArg]): CmdResult[int32] =
  sendMessage(source, "Saving...")
  saveAll(source)
  sendMessage(source, "Saved the server")
  cmdOk[int32](1'i32)

proc registerSaveAll*(t: var Tree) =
  let cmdNode = addLiteral(t, RootIndex, "save-all")
  setCommand(t, cmdNode, saveAllExecute)
  let flushNode = addLiteral(t, cmdNode, "flush")
  setCommand(t, flushNode, saveAllExecute)
