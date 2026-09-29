## Proves the command tree/dispatcher actually parses and runs a command,
## not just that it compiles - intended to be run with `nimony c -r`, the
## same bar as e.g. src/nbt/nbttest.nim or src/world/palettetest.nim.
##
## STATUS: `nimony check` passes clean on every file in this crate slice
## (cmdsource.nim, argtype.nim, cmdtree.nim, cmddispatch.nim, this file).
## Full codegen (`nimony c`/`c -r`) currently crashes the compiler at the
## lambda-lifting stage (`lambdalifting.nim(369) env.s != SymId(0)` /
## `eraiser.nim(128) fnType.tagEnum == ParamsTagId`, both internal
## AssertionDefects) once real closures actually flow through the
## `CommandNode`/`ArgumentType` vtables at runtime (assigning them to
## named `let`s first, rather than passing anonymous `proc(...)
## {.closure.} = ...` literals inline, was tried and made no difference).
## This is a DIFFERENT, deeper bug than the `for..in`-over-closure-seq one
## fixed in `cmdtree.nim`'s `meetsRequirements` (that one repros and fixes
## at the `nimony check` level already; this one only shows up at full
## codegen). Not minimally reduced or filed as feedback yet - that's the
## honest next step before trusting this dispatcher end-to-end, the same
## way `src/nbt/nbt_compress.nim`'s gzip wiring is "compiles clean, not
## proven at runtime here" rather than claimed working. Treat everything
## in this crate slice as semantically-checked, NOT runtime-verified.

import std/assertions
import std/syncio
import cmdsource, argtype, cmdtree, cmddispatch, cmderrors

# Build: "gamemode <mode:int>" and "spawn" (a bare executable literal).
# Closures are assigned to named local `let`s first, then passed - an
# inline anonymous `proc(...) {.closure.} = ...` literal directly as a
# call argument hit a *different* Nimony compiler crash than the
## `for..in`-over-closure-seq one (lambdalifting.nim `env.s != SymId(0)`,
# only at full `nimony c` codegen, not at `nimony check`) - not minimally
# reproduced/filed yet, this is the workaround found while writing this
# test.
let modeExecutor = proc(source: CommandSource, args: seq[ParsedArg]): CmdResult[int32] {.closure.} =
  let (found, value) = findArgSeq(args, "mode")
  if found and value.kind == avkInt:
    cmdOk[int32](value.intVal)
  else:
    cmdErr[int32](cekExpectedInt, "missing mode")

let gamemodeExecutor = proc(source: CommandSource, args: seq[ParsedArg]): CmdResult[int32] {.closure.} =
  cmdErr[int32](cekExpectedInt, "gamemode requires a mode")

let spawnExecutor = proc(source: CommandSource, args: seq[ParsedArg]): CmdResult[int32] {.closure.} =
  cmdOk[int32](1)

var t = newTree()
let gamemodeLit = addLiteral(t, RootIndex, "gamemode")
let modeArg = addArgument(t, gamemodeLit, "mode", newIntegerArgumentType(0, 3))
setCommand(t, modeArg, modeExecutor)
setCommand(t, gamemodeLit, gamemodeExecutor)

let spawnLit = addLiteral(t, RootIndex, "spawn", executable = true)
setCommand(t, spawnLit, spawnExecutor)

let source = newDummySource()

# 1. "gamemode 2" should parse through both nodes and execute the leaf.
let r1 = executeCommand(t, "gamemode 2", source)
assert r1.isOk, "gamemode 2 should succeed"
assert r1.value == 2, "gamemode 2 should return the parsed mode"

# 2. "spawn" (bare literal, no argument) should execute directly.
let r2 = executeCommand(t, "spawn", source)
assert r2.isOk, "spawn should succeed"
assert r2.value == 1

# 3. Out-of-range argument should fail with a syntax error, not crash.
let r3 = executeCommand(t, "gamemode 99", source)
assert not r3.isOk, "gamemode 99 should fail (out of 0..3 range)"

# 4. Unknown command should fail cleanly.
let r4 = executeCommand(t, "nosuchcommand", source)
assert not r4.isOk, "unknown command should fail"

echo "all command dispatch checks passed"
