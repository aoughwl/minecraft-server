## The `/return` command.
## Port of upstream/pumpkin/src/command/commands/return.rs
##
## Named `returncmd.nim`, not `return.nim` - `return` is a reserved word in
## Nimony.
##
## Not ported: permission-registry registration (plain string stands in,
## same simplification as the rest of this port).

import ../../command/cmdtree, ../../command/cmdsource, ../../command/argtype,
       ../../command/cmderrors, ../../command/cmddispatch

const
  ReturnDescription* = "Controls execution flow in functions and sets return values."
  ReturnPermission* = "minecraft:command.return"

proc returnValueExecute(source: CommandSource, args: seq[ParsedArg]): CmdResult[int32] =
  let (foundArg, argVal) = findArgSeq(args, "value")
  if not foundArg or argVal.kind != avkInt:
    return cmdErr[int32](cekInvalidBool, "Missing or malformed 'value' argument")
  cmdOk[int32](argVal.intVal)

proc returnFailExecute(source: CommandSource, args: seq[ParsedArg]): CmdResult[int32] =
  cmdOk[int32](0'i32)

proc registerReturn*(t: var Tree) =
  let cmdNode = addLiteral(t, RootIndex, "return")
  let valueArg = addArgument(t, cmdNode, "value", newIntegerArgumentType())
  setCommand(t, valueArg, returnValueExecute)
  let failNode = addLiteral(t, cmdNode, "fail", executable = true)
  setCommand(t, failNode, returnFailExecute)
  let runNode = addLiteral(t, cmdNode, "run")
  setRedirect(t, runNode, RootIndex)
