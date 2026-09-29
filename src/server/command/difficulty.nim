## The `/difficulty` command.
## Port of upstream/pumpkin/src/command/commands/difficulty.rs
##
## Query (`/difficulty`) and set (`/difficulty <peaceful|easy|normal|hard>`)
## forms, both wired to `CommandSource.difficultyProc`/`setDifficultyProc`
## since no `Server`/`Level`/world-registry type exists in this port yet.
##
## Not ported: permission-registry registration (needs the unported
## `pumpkin_util::permission` module) and the translated feedback messages
## (`TextComponent::translate_cross` -> plain strings, same simplification
## the rest of this port uses for the unported `text` module).

import ../../command/cmdtree, ../../command/cmdsource, ../../command/cmderrors
import ../../util/difficulty

const
  DifficultyDescription* = "Query or change the difficulty of the world."
  DifficultyPermission* = "minecraft:command.difficulty"

proc difficultyQueryExecute(source: CommandSource, args: seq[ParsedArg]): CmdResult[int32] =
  let d = getDifficulty(source)
  sendMessage(source, "The difficulty is " & name(d))
  cmdOk[int32](ord(d).int32)

proc makeDifficultySetExecute(target: Difficulty): proc(source: CommandSource, args: seq[ParsedArg]): CmdResult[int32] {.closure.} =
  proc exec(source: CommandSource, args: seq[ParsedArg]): CmdResult[int32] {.closure.} =
    let current = getDifficulty(source)
    if current == target:
      return cmdErr[int32](cekInvalidBool, "The difficulty is already " & name(target))
    setDifficulty(source, target)
    let effective = getDifficulty(source)
    sendMessage(source, "The difficulty has been set to " & name(effective))
    cmdOk[int32](0'i32)
  exec

proc registerDifficulty*(t: var Tree) =
  ## Port of `register()`'s tree shape: four literal set-branches plus a
  ## query default at the `difficulty` node itself (upstream's
  ## `.executes(DifficultyQueryExecutor)` on the command node before the
  ## `.then(...)` branches).
  let cmdNode = addLiteral(t, RootIndex, "difficulty")
  setCommand(t, cmdNode, difficultyQueryExecute)

  let peacefulNode = addLiteral(t, cmdNode, "peaceful")
  setCommand(t, peacefulNode, makeDifficultySetExecute(Peaceful))
  let easyNode = addLiteral(t, cmdNode, "easy")
  setCommand(t, easyNode, makeDifficultySetExecute(Easy))
  let normalNode = addLiteral(t, cmdNode, "normal")
  setCommand(t, normalNode, makeDifficultySetExecute(Normal))
  let hardNode = addLiteral(t, cmdNode, "hard")
  setCommand(t, hardNode, makeDifficultySetExecute(Hard))
