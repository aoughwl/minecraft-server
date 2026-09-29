## The `/setidletimeout` command.
## Port of upstream/pumpkin/src/command/commands/setidletimeout.rs
##
## Not ported: permission-registry registration, translated feedback text
## (plain strings stand in, same simplification the rest of this port
## uses). `idleTimeoutProc` stands in for
## `context.server().player_idle_timeout.store(...)` - no `Server` type
## exists in this port yet; `nil` is a safe no-op (the argument is still
## parsed and echoed, proving the dispatch path).

import ../../command/cmdtree, ../../command/cmdsource, ../../command/argtype,
       ../../command/cmderrors, ../../command/cmddispatch

const
  SetIdleTimeoutDescription* = "Sets the time before idle players are kicked from the server."
  SetIdleTimeoutPermission* = "minecraft:command.setidletimeout"

proc setIdleTimeoutExecute(source: CommandSource, args: seq[ParsedArg]): CmdResult[int32] =
  let (foundArg, argVal) = findArgSeq(args, "minutes")
  if not foundArg or argVal.kind != avkInt:
    return cmdErr[int32](cekInvalidBool, "Missing or malformed 'minutes' argument")
  let minutes = argVal.intVal
  if minutes < 0:
    return cmdErr[int32](cekInvalidBool, "'minutes' must be non-negative")

  if source.idleTimeoutProc != nil:
    source.idleTimeoutProc(minutes)

  if minutes == 0:
    sendMessage(source, "Disabled the idle timeout")
  else:
    sendMessage(source, "Set the idle timeout to " & $minutes & " minutes")
  cmdOk[int32](minutes)

proc registerSetIdleTimeout*(t: var Tree) =
  let cmdNode = addLiteral(t, RootIndex, "setidletimeout")
  let argNode = addArgument(t, cmdNode, "minutes", newIntegerArgumentType(min = 0'i32))
  setCommand(t, argNode, setIdleTimeoutExecute)
