## The `/me <action>` command.
## Port of upstream/pumpkin/src/command/commands/me.rs
##
## Not ported: permission-registry registration and the translated
## `EMOTE_COMMAND` message-type tag - same simplifications as say.nim,
## which this is structurally identical to (upstream shares the shape,
## just a different literal/description/permission-default).

import ../../command/cmdtree, ../../command/cmdsource, ../../command/argtype,
       ../../command/cmderrors, ../../command/cmddispatch

const
  MeDescription* = "Broadcasts a narrative message about yourself."
  MePermission* = "minecraft:command.me"

proc meExecute(source: CommandSource, args: seq[ParsedArg]): CmdResult[int32] =
  let (foundArg, argVal) = findArgSeq(args, "action")
  if not foundArg or argVal.kind != avkString:
    return cmdErr[int32](cekInvalidBool, "Missing or malformed 'action' argument")
  broadcastMessage(source, argVal.stringVal)
  cmdOk[int32](1'i32)

proc registerMe*(t: var Tree) =
  let cmdNode = addLiteral(t, RootIndex, "me")
  let argNode = addArgument(t, cmdNode, "action", newStringArgumentType(sakGreedy))
  setCommand(t, argNode, meExecute)
