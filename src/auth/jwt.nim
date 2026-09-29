## JWT verifier for Minecraft: Bedrock Edition - the data model, base64
## plumbing, and P-384 ECDSA chain-of-trust verification.
## Port of upstream/auth/src/jwt/mod.rs
##
## Rust's actual signature verification (`build_public_key_from_b64`,
## the chain-of-trust check against Mojang's key, `VerifyingKey::verify`)
## depends on the `p384`/`ecdsa` crates for NIST P-384 ECDSA. Nimony's
## own stdlib has no elliptic-curve primitives, so the P-384/ES384
## verification this needs comes from a standalone sibling library,
## `../jwt` (github.com/aoughwl/jwt once published - local-only as of
## this writing), built specifically to unblock this. It's pulled in as
## a real cross-repo import via this repo's `nimony.paths` (adds
## `../jwt/src` to the module search path), not vendored - see that
## repo's README for what's implemented and how it's verified
## (FIPS/RFC/Wycheproof test vectors, not hand-typed crypto constants).

import std/base64
import std/md5
import ecdsa, sha2, minijson

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

# --- crypto-dependent surface: now wired to ../jwt's P-384 ECDSA primitives ---

proc decodeUrlSafePadded(s: string): JwtResult[seq[byte]] =
  ## `URL_SAFE` (URL-safe alphabet, WITH padding) - the one variant
  ## `decodeB64Standard`/`decodeB64UrlNoPad` don't already cover.
  var padded = s
  let rem = padded.len mod 4
  if rem != 0:
    for _ in 0 ..< (4 - rem): padded.add('=')
  var std = newString(padded.len)
  for i, c in padded:
    if c == '-': std[i] = '+'
    elif c == '_': std[i] = '/'
    else: std[i] = c
  decodeB64Standard(std)

proc buildPublicKeyFromB64*(b64: string): JwtResult[seq[byte]] =
  ## Port of `build_public_key_from_b64`. Tries STANDARD, then URL_SAFE,
  ## then URL_SAFE_NO_PAD decoding (matching upstream's fallback chain),
  ## then accepts the bytes as a SEC1 P-384 public key: either the full
  ## 97-byte uncompressed form (0x04 || X || Y) or a bare 96-byte X||Y
  ## pair, which gets the 0x04 prefix restored the same way upstream does.
  ##
  ## PKCS#8/SPKI DER-encoded keys (leading 0x30 byte) are NOT supported -
  ## `../jwt` has no ASN.1/DER decoder yet (see that repo's README, "DER-
  ## encoded ECDSA signatures" - same gap applies to DER-encoded keys).
  ## Real Bedrock chain-of-trust `x5u` values are SEC1-uncompressed, so
  ## this covers the actual need; a DER key here returns `aekPublicKeyBuild`.
  var bytesRes = decodeB64Standard(b64)
  if not bytesRes.isOk:
    bytesRes = decodeUrlSafePadded(b64)
  if not bytesRes.isOk:
    bytesRes = decodeB64UrlNoPad(b64)
  if not bytesRes.isOk:
    return errRes[seq[byte]](aekBase64Decode, "couldn't base64-decode public key")

  let bytes = bytesRes.value
  if bytes.len == 0:
    return errRes[seq[byte]](aekPublicKeyBuild, "empty public key")
  if bytes[0] == 0x30'u8:
    return errRes[seq[byte]](aekPublicKeyBuild,
      "DER-encoded public keys are not supported (no ASN.1 decoder in ../jwt yet)")
  if bytes.len == 97 and bytes[0] == 0x04'u8:
    return ok[seq[byte]](bytes)
  if bytes.len == 96:
    var sec1 = newSeq[byte](97)
    sec1[0] = 0x04'u8
    for i in 0 ..< 96: sec1[i + 1] = bytes[i]
    return ok[seq[byte]](sec1)
  errRes[seq[byte]](aekPublicKeyBuild,
    "unsupported key format/length: " & $bytes.len & " bytes")

proc decodeHeaderGetX5u*(headerB64: string): JwtResult[string] =
  ## Port of `decode_header_get_x5u`.
  let headerBytesRes = decodeB64UrlNoPad(headerB64)
  if not headerBytesRes.isOk:
    return errRes[string](headerBytesRes.error.kind, headerBytesRes.error.msg)
  var headerStr = newString(headerBytesRes.value.len)
  for i, b in headerBytesRes.value: headerStr[i] = char(b)
  let parsed = parseJson(headerStr)
  if not parsed.ok or parsed.value == nil:
    return errRes[string](aekJsonParse, "invalid header JSON: " & parsed.error)
  let x5u = objGet(parsed.value, "x5u")
  if x5u == nil or x5u.kind != jkString:
    return errRes[string](aekMissingX5U, "x5u not found in header")
  ok[string](x5u.strVal)

proc bytesToStr(b: seq[byte]): string =
  result = newString(b.len)
  for i, x in b: result[i] = char(x)

proc strToBytes(s: string): seq[byte] =
  result = newSeq[byte](s.len)
  for i, c in s: result[i] = byte(c)

proc verifyEs384Token*(token: string, pubKey: seq[byte]): JwtResult[nil JsonValue] =
  ## Verifies a compact JWT's ES384 signature against `pubKey` (a 97-byte
  ## SEC1-uncompressed P-384 point, as returned by `buildPublicKeyFromB64`)
  ## and returns its parsed, decoded payload. Does not check `exp`/`aud`/
  ## `iss` claims - callers that need those (the way upstream's
  ## `verify_oidc_claims` does) check them on the returned payload.
  var headerB64 = ""
  var payloadB64 = ""
  var sigB64 = ""
  var seg = 0
  for c in token:
    if c == '.':
      inc seg
    elif seg == 0: headerB64.add(c)
    elif seg == 1: payloadB64.add(c)
    elif seg == 2: sigB64.add(c)
  if seg != 2 or headerB64.len == 0 or payloadB64.len == 0 or sigB64.len == 0:
    return errRes[nil JsonValue](aekInvalidTokenFormat, "expected 3 dot-separated segments")

  let sigRes = decodeB64UrlNoPad(sigB64)
  if not sigRes.isOk:
    return errRes[nil JsonValue](sigRes.error.kind, sigRes.error.msg)
  if sigRes.value.len != 96:
    return errRes[nil JsonValue](aekInvalidSignature,
      "ES384 signature must be 96 bytes (r||s), got " & $sigRes.value.len)
  var rBytes = newSeq[byte](48)
  var sBytes = newSeq[byte](48)
  for i in 0 ..< 48:
    rBytes[i] = sigRes.value[i]
    sBytes[i] = sigRes.value[48 + i]

  let signingInput = strToBytes(headerB64 & "." & payloadB64)
  let hash = sha384(signingInput)
  if not verifyEcdsaP384(pubKey, hash, rBytes, sBytes):
    return errRes[nil JsonValue](aekInvalidSignature, "Invalid signature")

  let payloadBytesRes = decodeB64UrlNoPad(payloadB64)
  if not payloadBytesRes.isOk:
    return errRes[nil JsonValue](payloadBytesRes.error.kind, payloadBytesRes.error.msg)
  let payloadParse = parseJson(bytesToStr(payloadBytesRes.value))
  let payloadVal = payloadParse.value
  if not payloadParse.ok or payloadVal == nil:
    return errRes[nil JsonValue](aekJsonParse, "invalid payload JSON: " & payloadParse.error)
  ok[nil JsonValue](payloadVal)

proc jsonGetStr(v: nil JsonValue, key: string): string =
  if v == nil: return ""
  let f = objGet(v, key)
  if f == nil or f.kind != jkString: return ""
  f.strVal

proc xuidToUuid*(xuid: string): string =
  ## Port of `xuid_to_uuid`: an MD5-namespace-UUID derivation (variant/
  ## version bits forced to a valid v3-shaped UUID) of `"pocket-auth-1-
  ## xuid:" & xuid`, formatted as a standard dashed UUID string.
  var digest = toMD5("pocket-auth-1-xuid:" & xuid)
  digest[6] = (digest[6] and 0x0f'u8) or 0x30'u8
  digest[8] = (digest[8] and 0x3f'u8) or 0x80'u8
  var hex = ""
  const hexChars = "0123456789abcdef"
  for b in digest:
    hex.add(hexChars[int(b shr 4)])
    hex.add(hexChars[int(b and 0x0f'u8)])
  hex[0 ..< 8] & "-" & hex[8 ..< 12] & "-" & hex[12 ..< 16] & "-" &
    hex[16 ..< 20] & "-" & hex[20 ..< 32]

proc extractPlayerClaims*(payload: nil JsonValue): PlayerClaims =
  ## Port of `extract_oidc_player_claims`.
  let displayName = jsonGetStr(payload, "xname")
  let xuid = jsonGetStr(payload, "xid")
  var uuid: string
  if xuid.len == 0:
    let leguuid = jsonGetStr(payload, "leguuid")
    uuid = (if leguuid.len == 0: xuidToUuid(xuid) else: leguuid)
  else:
    uuid = xuidToUuid(xuid)
  PlayerClaims(displayName: displayName, uuid: uuid, xuid: xuid)

proc verifyOidcTokenSelfSigned*(token: string): JwtResult[PlayerClaims] =
  ## Port of `verify_oidc_token_self_signed`: the ES384 self-signed-token
  ## path only (the `x5u` header's embedded key IS the signer - there is
  ## no separate JWKS lookup or issuer check here, matching upstream's
  ## `expected_issuer: None` call site). Upstream's RS256 path and the
  ## issuer-checked `verify_oidc_token` (needs a fetched JWKS) are not
  ## ported - both need pieces `../jwt` doesn't have yet (RSA, and this
  ## repo doesn't have an HTTP client to fetch a JWKS with, see
  ## src/auth/client.nim).
  var headerB64 = ""
  for c in token:
    if c == '.': break
    headerB64.add(c)
  if headerB64.len == 0:
    return errRes[PlayerClaims](aekInvalidTokenFormat, "Invalid token format")

  let x5uRes = decodeHeaderGetX5u(headerB64)
  if not x5uRes.isOk:
    return errRes[PlayerClaims](x5uRes.error.kind, x5uRes.error.msg)
  let pubKeyRes = buildPublicKeyFromB64(x5uRes.value)
  if not pubKeyRes.isOk:
    return errRes[PlayerClaims](pubKeyRes.error.kind, pubKeyRes.error.msg)

  let payloadRes = verifyEs384Token(token, pubKeyRes.value)
  if not payloadRes.isOk:
    return errRes[PlayerClaims](payloadRes.error.kind, payloadRes.error.msg)
  ok[PlayerClaims](extractPlayerClaims(payloadRes.value))

# --- still blocked / not ported ---------------------------------------------
#
# - The Mojang-root-of-trust chain walk (upstream's multi-link
#   `verify_jwt_chain`-shaped logic, checking the final link's key against
#   a hardcoded, known-good Mojang root public key constant): not written
#   here because that root key is itself a security-critical constant that
#   must come from a verified source, the same discipline `../jwt`'s
#   README describes for its own curve-parameter constants ("never typed
#   from memory and trusted blindly") - it should be added alongside a
#   citation of where it was fetched from, not guessed.
# - RS256 (needs RSA - `../jwt`'s bignum.nim has `bnModPow`, the rest
#   is PKCS#1 v1.5 padding + DER key parsing, both unwritten).
# - `verify_oidc_token`'s issuer-checked, JWKS-fetching path: needs both
#   RS256 (some OIDC providers sign with it) and an HTTP client to fetch
#   the JWKS from (src/auth/client.nim is an unported stub - see its
#   own doc comment).
