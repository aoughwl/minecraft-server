## JWT verifier for Minecraft: Bedrock Edition - the data model and
## base64 plumbing.
## Port of upstream/auth/src/jwt/mod.rs
##
## Rust's actual signature verification (`build_public_key_from_b64`,
## the chain-of-trust check against Mojang's key, `VerifyingKey::verify`)
## depends on the `p384`/`ecdsa` crates for NIST P-384 ECDSA. Nimony's
## stdlib (~/nimony/lib/std/) has `sha1` but no elliptic-curve primitives
## at all - no P-384, no generic ECDSA verify. That's a hard blocker, not
## a style choice: porting it would mean hand-rolling P-384 field/curve
## arithmetic and ECDSA verification from scratch, which is real
## cryptographic-implementation work, not a mechanical Rust->Nimony
## translation. So this file ports the parts that don't need it (claims
## model, error kinds, base64 decoding) and leaves the crypto-dependent
## functions as explicit TODOs. Bedrock JWT verification cannot work
## until a P-384 ECDSA verify primitive exists somewhere in the Nimony
## ecosystem (stdlib or a vendored implementation).

import std/base64

type
  PlayerClaims* = object
    ## The claims extracted from a Bedrock player's JWT token.
    displayName*: string
    uuid*: string
    xuid*: string

  AuthErrorKind* = enum
    aekInvalidTokenFormat
    aekMissingX5U
    aekBase64Decode
    aekJsonParse
    aekPublicKeyBuild
    aekMojangKeyMismatch
    aekInvalidSignature
    aekEcdsa

  AuthError* = object
    kind*: AuthErrorKind
    msg*: string

  JwtResult*[T] = object
    case isOk*: bool
    of true:
      value*: T
    of false:
      error*: AuthError

proc ok*[T](value: sink T): JwtResult[T] =
  JwtResult[T](isOk: true, value: value)

proc errRes*[T](kind: AuthErrorKind, msg: string): JwtResult[T] =
  JwtResult[T](isOk: false, error: AuthError(kind: kind, msg: msg))

proc invalidTokenFormat*(): AuthError =
  AuthError(kind: aekInvalidTokenFormat, msg: "Invalid token format")

proc missingX5U*(): AuthError =
  AuthError(kind: aekMissingX5U, msg: "x5u not found in header")

proc mojangKeyMismatch*(): AuthError =
  AuthError(kind: aekMojangKeyMismatch, msg: "Token not signed by trusted Mojang key")

proc invalidSignature*(): AuthError =
  AuthError(kind: aekInvalidSignature, msg: "Invalid signature")

# --- base64 -----------------------------------------------------------------
#
# Rust reaches for three alphabets via the `base64` crate's named engines
# (`STANDARD`, `URL_SAFE`, `URL_SAFE_NO_PAD`). `std/base64.decode` in
# Nimony's stdlib only understands the standard `+`/`/` alphabet with `=`
# padding, so the URL-safe variants are normalized to that before decoding.

proc normalizeToStandardB64(s: string): string =
  result = newString(s.len)
  for i, c in s:
    if c == '-': result[i] = '+'
    elif c == '_': result[i] = '/'
    else: result[i] = c
  let rem = result.len mod 4
  if rem != 0:
    for _ in 0 ..< (4 - rem):
      result.add('=')

proc decodeB64Standard*(s: string): JwtResult[seq[byte]] =
  ## Port of `decode_b64_standard`. `std/base64.decode` raises on malformed
  ## input via Nimony's ErrorCode mechanism rather than returning a
  ## Result, and this crate's whole error model is "no exceptions" (see
  ## nbtbase.nim's design note) - so this doesn't catch that failure yet.
  ## TODO: once Nimony's raise/except surfaces a catchable ErrorCode here,
  ## wrap this and turn a decode failure into `errRes(aekBase64Decode, ...)`
  ## instead of propagating the raise.
  let decoded = base64.decode(s)
  var bytes = newSeq[byte](decoded.len)
  for i, c in decoded:
    bytes[i] = byte(c)
  ok[seq[byte]](bytes)

proc decodeB64UrlNoPad*(s: string): JwtResult[seq[byte]] =
  ## Port of `decode_b64_url_nopad`.
  decodeB64Standard(normalizeToStandardB64(s))

# --- crypto-dependent surface: TODO, blocked on P-384 ECDSA ----------------
#
# proc buildPublicKeyFromB64*(b64: string): JwtResult[???]
#   Port of `build_public_key_from_b64`: tries STANDARD, then URL_SAFE,
#   then URL_SAFE_NO_PAD decoding, then parses the bytes as a P-384 public
#   key (SEC1 or PKCS#8 DER). Blocked: no P-384 point/key type in Nimony.
#
# proc verifyJwtChain*(...): JwtResult[PlayerClaims]
#   The actual chain-of-trust walk: decode each JWT segment, extract the
#   `x5u` header's embedded public key, verify the previous link's
#   signature against it, and check the final key matches Mojang's known
#   root. Blocked: needs `buildPublicKeyFromB64` plus an ECDSA-P384
#   `verify(signature, message, publicKey): bool`.
