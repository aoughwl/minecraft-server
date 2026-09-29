## The `/say <message>` command.
## Port of upstream/pumpkin/src/command/commands/say.rs
##
## Not ported: permission-registry registration (needs the unported
## `pumpkin_util::permission` module, same simplification as gamemode.nim),
## and the translated `SAY_COMMAND` message-type tag (needs unported
## `pumpkin_data::world`/`text` - the message is broadcast as plain text
## instead of a structured, colorable component).

import ../../command/cmdtree, ../../command/cmdsource, ../../command/argtype,
       ../../command/cmderrors, ../../command/cmddispatch

const
  SayDescription* = "Broadcast a message to all Players."
  SayPermission* = "minecraft:command.say"

proc sayExecute(source: CommandSource, args: seq[ParsedArg]): CmdResult[int32] =
  let (foundArg, argVal) = findArgSeq(args, "message")
  if not foundArg or argVal.kind != avkString:
    return cmdErr[int32](cekInvalidBool, "Missing or malformed 'message' argument")
  broadcastMessage(source, argVal.stringVal)
  cmdOk[int32](1'i32)

proc registerSay*(t: var Tree) =
  let cmdNode = addLiteral(t, RootIndex, "say")
  let argNode = addArgument(t, cmdNode, "message", newStringArgumentType(sakGreedy))
  setCommand(t, argNode, sayExecute)
