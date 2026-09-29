## Shared error/result plumbing for the protocol crate.
## Port of pumpkingmc/crates/pumpkin-protocol/src/ser/mod.rs's
## `ReadingError`/`WritingError` (the non-serde-trait parts).
##
## Follows the house convention established in src/nbt/nbtbase.nim: Nimony
## has no Nim-compatible exceptions, so every fallible proc returns an
## explicit result object instead of raising.

type
  ReadingErrorKind* = enum
    reCleanEof     ## Upstream `CleanEOF`: EOF right at a packet boundary,
                    ## not mid-payload - the caller (e.g. an accept loop)
                    ## treats this as "connection closed", not a protocol
                    ## violation.
    reIncomplete
    reTooLarge
    reMessage

  ReadingError* = object
    kind*: ReadingErrorKind
    msg*: string

  WritingErrorKind* = enum
    weIoError
    weSerde
    weUnsupportedVersion
    weMessage

  WritingError* = object
    kind*: WritingErrorKind
    msg*: string

  ProtoReadResult*[T] = object
    case isOk*: bool
    of true: value*: T
    of false: error*: ReadingError

  ProtoWriteResult*[T] = object
    case isOk*: bool
    of true: value*: T
    of false: error*: WritingError

  ProtoWriteVoidResult* = object
    isOk*: bool
    error*: WritingError

proc readOk*[T](value: sink T): ProtoReadResult[T] =
  ProtoReadResult[T](isOk: true, value: value)

proc readErr*[T](e: ReadingError): ProtoReadResult[T] =
  ProtoReadResult[T](isOk: false, error: e)

proc writeOkVoid*(): ProtoWriteVoidResult =
  ProtoWriteVoidResult(isOk: true)

proc writeErrVoid*(e: WritingError): ProtoWriteVoidResult =
  ProtoWriteVoidResult(isOk: false, error: e)

proc cleanEof*(what: string): ReadingError =
  ReadingError(kind: reCleanEof, msg: "EOF, Tried to read " & what & " but No bytes left to consume")

proc incompleteRead*(msg: string): ReadingError =
  ReadingError(kind: reIncomplete, msg: "incomplete: " & msg)

proc tooLarge*(what: string): ReadingError =
  ReadingError(kind: reTooLarge, msg: "too large: " & what)

proc ioError*(msg: string): WritingError =
  WritingError(kind: weIoError, msg: "IO error: " & msg)
