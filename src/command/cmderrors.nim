## Command-parsing error types.
## Port of pumpkingmc/crates/pumpkin-command/src/errors/command_syntax_error.rs
## (simplified) and (the shape of) src/errors/error_types.rs.
##
## Upstream's `CommandSyntaxError` carries `error_type: &'static dyn
## AnyCommandErrorType` (a trait object identifying *which* static error
## constant fired, e.g. `READER_EXPECTED_INT`) plus a `TextComponent`
## message (pumpkin_util::text, itself not yet ported - a prior fork
## skipped `text/mod.rs`, ~2.2k lines). Reproducing that trait-object
## registry faithfully needs both of those first. Until then, this is a
## plain `kind` enum (one variant per upstream error-type constant actually
## used by string_reader.rs) plus a plain `string` message - functionally
## equivalent for the parser logic that needs to exist now, but NOT wired
## to `error_types.rs`'s exact identity-compare semantics (`CommandSyntaxError::is`)
## or to real client-facing `TextComponent` formatting. Revisit once
## text/mod.rs and error_types.rs are ported.

type
  CmdErrorKind* = enum
    cekExpectedBool
    cekInvalidBool
    cekExpectedInt
    cekInvalidInt
    cekExpectedLong
    cekInvalidLong
    cekExpectedFloat
    cekInvalidFloat
    cekExpectedDouble
    cekInvalidDouble
    cekExpectedStartQuote
    cekExpectedEndQuote
    cekInvalidEscape
    cekExpectedSymbol

  CommandSyntaxErrorContext* = object
    input*: string
    cursor*: int

  CommandSyntaxError* = object
    kind*: CmdErrorKind
    message*: string
    hasContext*: bool
    context*: CommandSyntaxErrorContext

  CmdResult*[T] = object
    case isOk*: bool
    of true:
      value*: T
    of false:
      error*: CommandSyntaxError

  CmdVoidResult* = object
    isOk*: bool
    error*: CommandSyntaxError

proc cmdOk*[T](value: sink T): CmdResult[T] =
  CmdResult[T](isOk: true, value: value)

proc cmdErr*[T](kind: CmdErrorKind, message: string): CmdResult[T] =
  CmdResult[T](isOk: false, error: CommandSyntaxError(kind: kind, message: message, hasContext: false))

proc cmdOkVoid*(): CmdVoidResult =
  CmdVoidResult(isOk: true)

proc cmdErrVoid*(kind: CmdErrorKind, message: string): CmdVoidResult =
  CmdVoidResult(isOk: false, error: CommandSyntaxError(kind: kind, message: message, hasContext: false))
