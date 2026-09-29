## HTTP client utilities.
## Port of upstream/auth/src/client.rs
##
## Upstream builds a `reqwest::Client` (rustls TLS, with a Mozilla
## root-cert fallback on Android). Nimony has no HTTP/TLS client in its
## own stdlib, so this is backed by the aoughwl `requests` library
## (../requests/nimony, added via nimony.paths) - a session-based HTTP
## client over curl-impersonate. `newDefaultClient()` mirrors upstream's
## `client()`: a ready-to-use client with sane defaults and TLS
## verification on. The Android-specific certificate-bundle branch has no
## analogue here (no Android target) and is dropped, same as it would be
## on any other desktop/server target upstream.
##
## Verification status: BLOCKED, does not currently compile. `requests`'s
## own `profiles.nim` defines `const builtins*: array[7, Profile] = [...]`
## where each `Profile` has a `seq[(string, string)]` field initialized
## with a `@[...]` literal; Nimony's compile-time evaluator rejects this
## ("cannot evaluate expression at compile time" on the `@(...)` seq
## literal inside the const array). This is a Nimony compiler/stdlib
## limitation inside a sibling project (github.com/aoughwl/requests), not
## a bug in this file or in `requests`'s design - not fixed here since
## that repo wasn't in scope for this pass. Once `requests` either works
## around it (e.g. `let` instead of `const`, or building `builtins` in a
## proc) or Nimony's const-eval improves, this file's shape should still
## be correct as-is. Also still true regardless: `requests` links
## `libcurl-impersonate.so` via a Linux-named `{.dynlib.}` with no
## Windows variant, and that specialized curl-impersonate binary isn't
## installed on this dev machine either way - full runtime proof needs
## the project's actual Linux deployment target.

import requests

type
  HttpClient* = object
    session*: Session

proc newDefaultClient*(): HttpClient =
  ## Port of `client()`/`client_builder()`: a client with TLS verification
  ## on and no proxy, matching upstream's non-Android default path.
  HttpClient(session: newSession(verifyTls = true))

proc get*(client: HttpClient, url: string, headers: seq[(string, string)] = @[]): Response =
  get(client.session, url, headers)

proc post*(client: HttpClient, url: string, body: string,
           headers: seq[(string, string)] = @[]): Response =
  post(client.session, url, body, headers)

proc close*(client: HttpClient) =
  close(client.session)
