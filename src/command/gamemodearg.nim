## GameMode argument type.
## Port of upstream/command/src/argument_types/gamemode.rs
##
## Wired into `ArgValue` as `avkString` (see uuidarg.nim's doc comment for
## the reasoning) holding the canonical lowercase name; call
## `../util/gamemode.parseGameMode` on it to get the `GameMode` value back.

import cmderrors, string_reader, argtype
import ../util/gamemode

proc newGameModeArgumentType*(): ArgumentType =
  ArgumentType(
    name: "gamemode",
    parseProc: proc(r: var StringReader): CmdResult[ArgValue] {.closure.} =
      let text = readUnquotedString(r)
      let (ok, _) = parseGameMode(text)
      if not ok:
        return cmdErr[ArgValue](cekInvalidBool, "Invalid game mode '" & text & "'")
      cmdOk[ArgValue](ArgValue(kind: avkString, stringVal: text)),
  )
