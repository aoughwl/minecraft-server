## A cursor-based reader over a command string: the core tokenizer every
## argument-type parser in this crate builds on.
## Port of pumpkingmc/crates/pumpkin-command/src/string_reader.rs
##
## Simplifications versus upstream:
## - Rust's `StringReader<'a>` wraps a `Cow<'a, str>` to avoid copying when
##   possible. Nimony's `string` is always owned with no borrow-slicing
##   story as cheap as `Cow`, so this just owns a `string` outright -
##   `intoOwned`/`cloneIntoOwned` (upstream's `'static`-snapshotting
##   helpers, needed only to escape the borrow) have no reason to exist
##   here and are dropped.
## - `peek`/`read`/`skip` advance by *byte*, not by decoded Unicode
##   scalar value. Command syntax (quotes, brackets, digits, `-`/`.`/`_`)
##   is ASCII, and quoted-string *contents* pass through byte-for-byte
##   either way, so this only diverges from upstream for non-ASCII bytes
##   inside an unquoted token or right at a boundary - not reachable by
##   any real vanilla command. TODO: switch to real UTF-8 scalar-value
##   stepping if `read`/`peek` need `char`-level fidelity later (e.g. for
##   arbitrary-Unicode string arguments).

import cmderrors

type
  StringReader* = object
    str: string
    byteCursor: int

const
  SyntaxEscape = '\\'
  SyntaxSingleQuote = '\''
  SyntaxDoubleQuote = '"'

proc newStringReader*(s: string): StringReader {.inline.} =
  StringReader(str: s, byteCursor: 0)

proc str*(r: StringReader): string {.inline.} =
  r.str

proc cursor*(r: StringReader): int {.inline.} =
  r.byteCursor

proc setCursor*(r: var StringReader, cursor: int) {.inline.} =
  r.byteCursor = cursor

proc totalLength*(r: StringReader): int {.inline.} =
  r.str.len

proc remainingLength*(r: StringReader): int {.inline.} =
  r.str.len - r.byteCursor

proc readPart*(r: StringReader): string {.inline.} =
  r.str[0 ..< r.byteCursor]

proc remainingPart*(r: StringReader): string {.inline.} =
  r.str[r.byteCursor .. ^1]

proc canReadBytes*(r: StringReader, length: int): bool {.inline.} =
  r.byteCursor + length <= r.str.len

proc canReadByte*(r: StringReader): bool {.inline.} =
  canReadBytes(r, 1)

proc byteAt*(r: StringReader, i: int): (bool, uint8) =
  if i >= 0 and i < r.str.len:
    (true, r.str[i].uint8)
  else:
    (false, 0'u8)

proc peekByte*(r: StringReader): (bool, uint8) =
  byteAt(r, r.byteCursor)

proc peek*(r: StringReader): (bool, char) =
  if r.byteCursor < r.str.len:
    (true, r.str[r.byteCursor])
  else:
    (false, '\0')

proc peekWithOffset*(r: StringReader, offset: int): (bool, char) =
  let i = r.byteCursor + offset
  if i < r.str.len:
    (true, r.str[i])
  else:
    (false, '\0')

proc read*(r: var StringReader): (bool, char) =
  let (has, c) = peek(r)
  if has:
    inc r.byteCursor
  (has, c)

proc skip*(r: var StringReader) =
  let (has, _) = peek(r)
  if has:
    inc r.byteCursor

proc isAllowedInNumber*(c: char): bool {.inline.} =
  (c >= '0' and c <= '9') or c == '.' or c == '-'

proc isAllowedAsQuotedStringStartEnd*(c: char): bool {.inline.} =
  c == SyntaxSingleQuote or c == SyntaxDoubleQuote

proc isAllowedInUnquotedString*(c: char): bool {.inline.} =
  (c >= '0' and c <= '9') or (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or
    c == '_' or c == '-' or c == '.' or c == '+'

proc charToStr(c: char): string {.inline.} =
  result = newString(1)
  result[0] = c

proc isWhitespaceChar(c: char): bool {.inline.} =
  c == ' ' or c == '\t' or c == '\n' or c == '\r'

proc skipWhitespace*(r: var StringReader) =
  while true:
    let (has, c) = peek(r)
    if has and isWhitespaceChar(c):
      skip(r)
    else:
      break

proc readUnquotedString*(r: var StringReader): string =
  let start = r.byteCursor
  while true:
    let (has, c) = peek(r)
    if has and isAllowedInUnquotedString(c):
      skip(r)
    else:
      break
  r.str[start ..< r.byteCursor]

proc readStringUntil*(r: var StringReader, terminator: char): CmdResult[string] =
  var res = ""
  var escaped = false
  while true:
    let (has, c) = peek(r)
    if not has:
      break
    if escaped:
      if c == terminator or c == SyntaxEscape:
        res.add(c)
        skip(r)
        escaped = false
      else:
        return cmdErr[string](cekInvalidEscape, "Invalid escape sequence '" & charToStr(c) & "' in quoted string")
    else:
      skip(r)
      if c == SyntaxEscape:
        escaped = true
      elif c == terminator:
        return cmdOk[string](res)
      else:
        res.add(c)
  cmdErr[string](cekExpectedEndQuote, "Unclosed quoted string")

proc readQuotedString*(r: var StringReader): CmdResult[string] =
  let (has, next) = peek(r)
  if not has:
    return cmdOk[string]("")
  if isAllowedAsQuotedStringStartEnd(next):
    skip(r)
    readStringUntil(r, next)
  else:
    cmdErr[string](cekExpectedStartQuote, "Expected quote to start a string")

proc readString*(r: var StringReader): CmdResult[string] =
  let (has, next) = peek(r)
  if not has:
    return cmdOk[string]("")
  if isAllowedAsQuotedStringStartEnd(next):
    skip(r)
    readStringUntil(r, next)
  else:
    cmdOk[string](readUnquotedString(r))

proc readBool*(r: var StringReader): CmdResult[bool] =
  let start = r.byteCursor
  let sr = readString(r)
  if not sr.isOk:
    return cmdErr[bool](sr.error.kind, sr.error.message)
  case sr.value
  of "":
    cmdErr[bool](cekExpectedBool, "Expected a boolean")
  of "true":
    cmdOk[bool](true)
  of "false":
    cmdOk[bool](false)
  else:
    r.byteCursor = start
    cmdErr[bool](cekInvalidBool, "Invalid boolean '" & sr.value & "'")

proc readNumericToken*(r: var StringReader, expectedKind: CmdErrorKind): CmdResult[string] =
  let start = r.byteCursor
  while true:
    let (has, c) = peek(r)
    if has and isAllowedInNumber(c):
      skip(r)
    else:
      break
  let res = r.str[start ..< r.byteCursor]
  if res.len == 0:
    return cmdErr[string](expectedKind, "Expected a number")
  cmdOk[string](res)

proc expect*(r: var StringReader, c: char): CmdVoidResult =
  let (has, p) = peek(r)
  if has and p == c:
    skip(r)
    cmdOkVoid()
  else:
    cmdErrVoid(cekExpectedSymbol, "Expected '" & charToStr(c) & "'")

proc readUntilSpace*(r: var StringReader) =
  while true:
    let (has, c) = peek(r)
    if not has or c == ' ':
      break
    skip(r)

# Numeric parsing procs (read_and_parse in upstream) live in a separate
# module (cmdnumbers.nim) since they need std/strutils-style parsing,
# to keep this file focused on the tokenizer.
