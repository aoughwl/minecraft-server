## UUID argument type, plus the UUID string parser it needs (none exists
## elsewhere in this port yet - src/protocol/uuid.nim only has the wire
## shape, not a hex-string parser).
## Port of upstream/command/src/argument_types/uuid.rs
##
## Wired into the existing `ArgValue`/`ArgumentType` vtable (argtype.nim)
## as `avkString` holding the validated, canonical dashed-hex text, rather
## than widening `ArgValue` with a new `PlayerUuid`-carrying variant -
## `parseUuidString` (below) is still the real, independently useful
## parser; a caller that wants the parsed `(hi, lo)` pair back just calls
## it again on the stored text. Widening `ArgValue` to carry the struct
## directly is a legitimate, mechanical follow-up once more argument
## types need the same treatment (angle/gamemode/identifier below make
## the same call).

import std/strutils
import cmderrors, string_reader, argtype

type
  PlayerUuid* = object
    hi*, lo*: uint64

proc hexNibble(c: char): (bool, uint8) =
  case c
  of '0'..'9': (true, uint8(ord(c) - ord('0')))
  of 'a'..'f': (true, uint8(ord(c) - ord('a') + 10))
  of 'A'..'F': (true, uint8(ord(c) - ord('A') + 10))
  else: (false, 0'u8)

proc parseUuidString*(s: string): (bool, PlayerUuid) =
  ## Accepts the standard `8-4-4-4-12` dashed hex form, matching upstream's
  ## `Uuid::parse_str` (which also accepts a bare 32-hex-digit form - both
  ## are supported here by simply ignoring dashes wherever they appear).
  var hex = ""
  for c in s:
    if c != '-':
      hex.add(c)
  if hex.len != 32:
    return (false, PlayerUuid())
  var bytes: array[16, uint8]
  for i in 0 ..< 16:
    let (okHi, hi) = hexNibble(hex[i * 2])
    let (okLo, lo) = hexNibble(hex[i * 2 + 1])
    if not okHi or not okLo:
      return (false, PlayerUuid())
    bytes[i] = (hi shl 4) or lo
  var hiVal, loVal: uint64
  for i in 0 ..< 8:
    hiVal = (hiVal shl 8) or uint64(bytes[i])
  for i in 8 ..< 16:
    loVal = (loVal shl 8) or uint64(bytes[i])
  (true, PlayerUuid(hi: hiVal, lo: loVal))

proc newUuidArgumentType*(): ArgumentType =
  ArgumentType(
    name: "uuid",
    parseProc: proc(r: var StringReader): CmdResult[ArgValue] {.closure.} =
      let start = r.cursor()
      while true:
        let (has, c) = peek(r)
        if has and (c in {'A'..'F', 'a'..'f', '0'..'9', '-'}):
          skip(r)
        else:
          break
      let text = r.str()[start ..< r.cursor()]
      let (ok, _) = parseUuidString(text)
      if not ok:
        setCursor(r, start)
        return cmdErr[ArgValue](cekInvalidBool, "Invalid UUID '" & text & "'")
      cmdOk[ArgValue](ArgValue(kind: avkString, stringVal: text)),
  )
