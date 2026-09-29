## HTTP client helpers for online license checks and marketplace queries.
## Port of upstream/plugin-utils/src/http.rs
##
## TODO: not implemented. Rust builds this on `reqwest::blocking::Client`
## (+ rustls). Nimony's stdlib has no HTTP client or TLS support at all
## (checked ~/nimony/lib/std/: only `errorcodes_http.nim`, an error-code
## enum, nothing that opens a connection). Real options once this is
## needed: FFI to libcurl (cross-platform, handles TLS) or WinHTTP on
## Windows specifically. This file keeps the call shape so callers
## (updater.nim, license.nim) can be written against it now and wired up
## later without changing their signatures.

import putbase

type
  HttpClient* = object
    userAgent*: string

proc newHttpClient*(userAgent = "Plugin-Utils/0.1.0"): HttpClient =
  HttpClient(userAgent: userAgent)

proc get*(c: HttpClient, url: string): PuResult[string] =
  errRes[string](notImplementedErr("HttpClient.get"))

proc postJson*(c: HttpClient, url: string, jsonPayload: string): PuResult[string] =
  errRes[string](notImplementedErr("HttpClient.postJson"))
