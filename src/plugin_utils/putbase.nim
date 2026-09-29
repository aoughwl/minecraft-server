## Shared error/result plumbing for the plugin-utils port.
## Port of the error enums scattered across plugin-utils'
## http.rs/updater.rs/license.rs. Nimony has no Nim-compatible exceptions
## (its raise/ErrorCode mechanism is a fixed, non-extensible enum), so every
## fallible Rust `Result<T,E>` here returns an explicit `PuResult[T]`
## instead - same house convention as src/nbt/nbtbase.nim and
## src/util/identifier.nim.

type
  PuErrorKind* = enum
    pekNotInitialized       ## `NotInitialized` (updater/license/lib)
    pekHttp                 ## `HttpError` wrapped from an HTTP call
    pekJson                 ## JSON (de)serialization failure
    pekMetadataMismatch     ## `LicenseError::MetadataMismatch`
    pekRevoked              ## `LicenseError::Revoked`
    pekExpired               ## `LicenseError::Expired`
    pekIo                    ## `LicenseError::Io`
    pekUnsignedPlugin        ## `LicenseError::UnsignedPlugin`
    pekRequestFailed         ## `HttpError::RequestFailed`
    pekBadStatus             ## `HttpError::BadStatus`
    pekBodyRead              ## `HttpError::BodyRead`
    pekNotImplemented        ## No Nimony HTTP client exists yet (see http.nim)

  PuError* = object
    kind*: PuErrorKind
    msg*: string

  PuResult*[T] = object
    case isOk*: bool
    of true:
      value*: T
    of false:
      error*: PuError

  PuVoidResult* = object
    ## `PuResult[void]` isn't legal (a void-typed object field doesn't
    ## compile), so `Result<()>`-shaped procs return this instead.
    isOk*: bool
    error*: PuError

proc ok*[T](value: sink T): PuResult[T] =
  PuResult[T](isOk: true, value: value)

proc errRes*[T](e: PuError): PuResult[T] =
  PuResult[T](isOk: false, error: e)

proc okVoid*(): PuVoidResult =
  PuVoidResult(isOk: true)

proc errVoid*(e: PuError): PuVoidResult =
  PuVoidResult(isOk: false, error: e)

proc puError*(kind: PuErrorKind, msg: string): PuError =
  PuError(kind: kind, msg: msg)

proc notInitializedErr*(): PuError =
  puError(pekNotInitialized,
    "Plugin-utils has not been initialized (call plugin_utils::init(context) first)")

proc notImplementedErr*(what: string): PuError =
  puError(pekNotImplemented, what & " is not implemented: Nimony has no HTTP client in " &
    "its stdlib yet (checked ~/nimony/lib/std/ - no http/net/url module beyond the " &
    "errorcodes_http.nim error-code enum). Needs a real HTTP+TLS client, likely via " &
    "C FFI (libcurl/WinHTTP) since this talks to the the upstream server Marketplace over HTTPS.")

proc urlencoding*(input: string): string =
  ## Port of the `urlencoding` helper duplicated in updater.rs/license.rs
  ## (percent-encodes everything but unreserved characters).
  result = ""
  for ch in input:
    let b = ch.uint8
    if (b >= 'a'.uint8 and b <= 'z'.uint8) or
       (b >= 'A'.uint8 and b <= 'Z'.uint8) or
       (b >= '0'.uint8 and b <= '9'.uint8) or
       ch == '-' or ch == '_' or ch == '.' or ch == '~':
      result.add(ch)
    else:
      const hexDigits = "0123456789ABCDEF"
      result.add('%')
      result.add(hexDigits[int(b shr 4)])
      result.add(hexDigits[int(b and 0x0F'u8)])
