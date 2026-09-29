## Argument types: how a raw token from a `StringReader` becomes a typed
## value at a `CommandNode::Argument`.
## Port of upstream/command/src/argument_types/argument_type.rs plus the
## concrete leaf types under argument_types/core/*.rs.
##
## Design decision (the second half of the one started in cmdsource.nim):
## upstream's `ArgumentType<S>` is generic over its parsed `Item` type, and
## `AnyArgumentType<S>` type-erases that via `Box<dyn Any + Send + Sync>` so
## a `CommandNode` can hold argument types of different `Item`s
## uniformly. Nimony has neither associated types on an interface nor
## `Any`/downcasting. Two ways to get the same effect: (a) constrained
## generics per call site, which doesn't work for a heterogeneous tree
## where sibling nodes parse different types, or (b) a closed, concrete
## union of "the types a command argument can produce" plus a manual
## vtable, matching the `Inventory`/`CommandSource` pattern already used
## elsewhere in this port. (b) is what this file does: `ArgValue` is a
## variant covering every `argument_types/core/*.rs` leaf type (bool, i32,
## i64, f32, f64, string) - the ones tokenizer.nim/cmdnumbers.nim already
## support parsing. The richer argument types (`block.rs`, `item.rs`,
## `nbt.rs`, `range.rs`, the `coordinates/` family, ...) all need real
## world/registry types this port doesn't have yet and are deliberately
## NOT covered by `ArgValue` - adding them means widening this variant,
## which is a small, mechanical follow-up once their backing types exist.
##
## `list_suggestions`/`SuggestionProviders`/`override_suggestion_providers`
## (client-side tab-complete) and `examples()` (used for ambiguity-conflict
## messages) are dropped entirely for this first pass - neither affects
## parse/dispatch correctness, which is what a first working tree needs to
## prove. `client_side_parser()` (which Java protocol argument-type enum
## this maps to, for sending the command tree to the client) is likewise
## deferred - it needs `pumpkin_protocol::java::client::play::ArgumentType`,
## itself unported.

import std/math
import cmderrors, string_reader, cmdnumbers, cmdsource

type
  ArgValueKind* = enum
    avkBool
    avkInt
    avkLong
    avkFloat
    avkDouble
    avkString

  ArgValue* = object
    case kind*: ArgValueKind
    of avkBool: boolVal*: bool
    of avkInt: intVal*: int32
    of avkLong: longVal*: int64
    of avkFloat: floatVal*: float32
    of avkDouble: doubleVal*: float64
    of avkString: stringVal*: string

  ArgumentType* = ref object
    ## Manual vtable, same shape as `Inventory`/`Slot`/`CommandSource`.
    ## `parseProc` is upstream's `parse` (source-independent parse, called
    ## when no `CommandSource` is available); `parseWithSourceProc`, if
    ## set, is `parse_with_source` - upstream defaults it to `parse`, which
    ## this reproduces via the `parseWithSource` wrapper below rather than
    ## requiring every constructor to fill it in.
    name*: string ## for error messages / debugging, not in upstream
    parseProc*: proc(r: var StringReader): CmdResult[ArgValue] {.closure.}
    parseWithSourceProc*: proc(r: var StringReader, source: CommandSource): CmdResult[ArgValue] {.closure.}

proc parse*(a: ArgumentType, r: var StringReader): CmdResult[ArgValue] =
  a.parseProc(r)

proc parseWithSource*(a: ArgumentType, r: var StringReader, source: CommandSource): CmdResult[ArgValue] =
  if a.parseWithSourceProc != nil:
    a.parseWithSourceProc(r, source)
  else:
    a.parseProc(r)

# --- core/bool.rs -----------------------------------------------------------

proc newBoolArgumentType*(): ArgumentType =
  ArgumentType(
    name: "bool",
    parseProc: proc(r: var StringReader): CmdResult[ArgValue] {.closure.} =
      let br = readBool(r)
      if not br.isOk:
        return cmdErr[ArgValue](br.error.kind, br.error.message)
      cmdOk[ArgValue](ArgValue(kind: avkBool, boolVal: br.value)),
  )

# --- core/integer.rs, core/long.rs ------------------------------------------

proc withinOrErr(reader: var StringReader, readerStart: int, value, min, max: int64,
                  tooLowMsg, tooHighMsg: string): CmdVoidResult =
  ## Port of `within_or_err`: on out-of-range, upstream resets the reader
  ## cursor back to before the number and reports the bound error there -
  ## reproduced via `setCursor`.
  if value < min:
    reader.setCursor(readerStart)
    return cmdErrVoid(cekInvalidInt, tooLowMsg & ": " & $value & " < " & $min)
  if value > max:
    reader.setCursor(readerStart)
    return cmdErrVoid(cekInvalidInt, tooHighMsg & ": " & $value & " > " & $max)
  cmdOkVoid()

proc newIntegerArgumentType*(min: int32 = int32.low, max: int32 = int32.high): ArgumentType =
  ArgumentType(
    name: "integer",
    parseProc: proc(r: var StringReader): CmdResult[ArgValue] {.closure.} =
      let start = r.cursor()
      let ir = readInt(r)
      if not ir.isOk:
        return cmdErr[ArgValue](ir.error.kind, ir.error.message)
      let bound = withinOrErr(r, start, int64(ir.value), int64(min), int64(max),
                               "Integer must not be less than " & $min,
                               "Integer must not be more than " & $max)
      if not bound.isOk:
        return cmdErr[ArgValue](bound.error.kind, bound.error.message)
      cmdOk[ArgValue](ArgValue(kind: avkInt, intVal: ir.value)),
  )

proc newLongArgumentType*(min: int64 = int64.low, max: int64 = int64.high): ArgumentType =
  ArgumentType(
    name: "long",
    parseProc: proc(r: var StringReader): CmdResult[ArgValue] {.closure.} =
      let start = r.cursor()
      let lr = readLong(r)
      if not lr.isOk:
        return cmdErr[ArgValue](lr.error.kind, lr.error.message)
      let bound = withinOrErr(r, start, lr.value, min, max,
                               "Long must not be less than " & $min,
                               "Long must not be more than " & $max)
      if not bound.isOk:
        return cmdErr[ArgValue](bound.error.kind, bound.error.message)
      cmdOk[ArgValue](ArgValue(kind: avkLong, longVal: lr.value)),
  )

# --- core/float.rs, core/double.rs ------------------------------------------

proc newFloatArgumentType*(min: float32 = -Inf.float32, max: float32 = Inf.float32): ArgumentType =
  ArgumentType(
    name: "float",
    parseProc: proc(r: var StringReader): CmdResult[ArgValue] {.closure.} =
      let start = r.cursor()
      let fr = readFloat(r)
      if not fr.isOk:
        return cmdErr[ArgValue](fr.error.kind, fr.error.message)
      if fr.value < min:
        r.setCursor(start)
        return cmdErr[ArgValue](cekInvalidFloat, "Float must not be less than " & $min)
      if fr.value > max:
        r.setCursor(start)
        return cmdErr[ArgValue](cekInvalidFloat, "Float must not be more than " & $max)
      cmdOk[ArgValue](ArgValue(kind: avkFloat, floatVal: fr.value)),
  )

proc newDoubleArgumentType*(min: float64 = -Inf, max: float64 = Inf): ArgumentType =
  ArgumentType(
    name: "double",
    parseProc: proc(r: var StringReader): CmdResult[ArgValue] {.closure.} =
      let start = r.cursor()
      let dr = readDouble(r)
      if not dr.isOk:
        return cmdErr[ArgValue](dr.error.kind, dr.error.message)
      if dr.value < min:
        r.setCursor(start)
        return cmdErr[ArgValue](cekInvalidDouble, "Double must not be less than " & $min)
      if dr.value > max:
        r.setCursor(start)
        return cmdErr[ArgValue](cekInvalidDouble, "Double must not be more than " & $max)
      cmdOk[ArgValue](ArgValue(kind: avkDouble, doubleVal: dr.value)),
  )

# --- core/string.rs ----------------------------------------------------------

type
  StringArgKind* = enum
    sakWord     ## a single unquoted token
    sakQuotable ## `readString`: quoted-or-unquoted
    sakGreedy   ## the rest of the input, verbatim

proc newStringArgumentType*(kind: StringArgKind): ArgumentType =
  ArgumentType(
    name: "string",
    parseProc: proc(r: var StringReader): CmdResult[ArgValue] {.closure.} =
      case kind
      of sakWord:
        cmdOk[ArgValue](ArgValue(kind: avkString, stringVal: readUnquotedString(r)))
      of sakQuotable:
        let sr = readString(r)
        if not sr.isOk:
          return cmdErr[ArgValue](sr.error.kind, sr.error.message)
        cmdOk[ArgValue](ArgValue(kind: avkString, stringVal: sr.value))
      of sakGreedy:
        let rest = remainingPart(r)
        r.setCursor(r.totalLength())
        cmdOk[ArgValue](ArgValue(kind: avkString, stringVal: rest)),
  )
