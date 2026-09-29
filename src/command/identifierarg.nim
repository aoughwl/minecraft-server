## Identifier (`namespace:path`) argument type.
## Port of upstream/command/src/argument_types/identifier.rs
##
## Upstream's `Identifier::from_reader` scans a different character class
## than `string_reader.nim`'s `readUnquotedString` (which is tuned for
## generic unquoted tokens, not resource locations): identifiers allow
## `:` and `/` too. Scans that class directly here rather than widening
## the shared tokenizer's charset, which other argument types rely on
## staying narrow.
##
## Wired into `ArgValue` as `avkString` (see uuidarg.nim's doc comment)
## holding the raw `namespace:path` text; call `../util/identifier.parse`
## on it to get a real `Identifier`/validate it structurally.

import cmderrors, string_reader, argtype
import ../util/identifier as identifiermod

proc isIdentifierChar(c: char): bool {.inline.} =
  (c >= '0' and c <= '9') or (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or
    c == '_' or c == '-' or c == '.' or c == '+' or c == ':' or c == '/'

proc newIdentifierArgumentType*(): ArgumentType =
  ArgumentType(
    name: "identifier",
    parseProc: proc(r: var StringReader): CmdResult[ArgValue] {.closure.} =
      let start = r.cursor()
      while true:
        let (has, c) = peek(r)
        if has and isIdentifierChar(c):
          skip(r)
        else:
          break
      let text = r.str()[start ..< r.cursor()]
      let idResult = identifiermod.parse(text)
      if not idResult.isOk:
        setCursor(r, start)
        return cmdErr[ArgValue](cekInvalidBool, "Invalid identifier '" & text & "'")
      cmdOk[ArgValue](ArgValue(kind: avkString, stringVal: text)),
  )
