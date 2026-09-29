## Integration smoke test proving src/auth/jwt.nim's P-384 ECDSA wiring
## (via ../jwt) actually verifies a real token end-to-end, not just that
## it compiles. Run with `nimony c -r src/auth/jwttest.nim` (PowerShell).

import std/assertions
import std/syncio
import std/base64
import minijson
import jwt

proc hv(c: char): int =
  if c >= '0' and c <= '9': ord(c) - ord('0')
  elif c >= 'a' and c <= 'f': ord(c) - ord('a') + 10
  elif c >= 'A' and c <= 'F': ord(c) - ord('A') + 10
  else: 0

proc bytesFromHex(s: string): seq[byte] =
  result = newSeq[byte](s.len div 2)
  var i = 0
  while i < s.len:
    result[i div 2] = uint8(hv(s[i]) * 16 + hv(s[i+1]))
    i += 2

proc bytesToStrPub(b: seq[byte]): string =
  result = newString(b.len)
  for i, x in b: result[i] = char(x)

# --- known-good vector, from ../jwt's own test_jwt.nim: a real ES384 JWT
# minted by Python's pycryptodome (an unrelated implementation), fresh
# random P-384 keypair. Its header has no x5u, so this exercises jwt.nim's
# lower-level verifyEs384Token-shaped path (via buildPublicKeyFromB64 and
# manual token splitting below), not the x5u-driven verifyOidcTokenSelfSigned.
let token = "eyJhbGciOiJFUzM4NCIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ0ZXN0LXVzZXIiLCJpYXQiOjE3MDAwMDAwMDAsImV4cCI6MTg5MzQ1NjAwMH0.a8u02fuWQ5A-pY_bIEfhGokpD-qSHI0c7B27Sq6sb1im8XIYiHMDA685QUfdt5-9FDAbecaTtrB5nj3-TxrVAP_-6_7_yRMj0l_5hI9jjgsbfGtTXdaRb5hiNv7_iUWY"
let pubKeyHex = "0400795e153e34ef959e470a1a2d49289c3e2790136de3a125adf4d19349d777c815a561a756300616401dead5d04e2e8a3cdeede220e72775b72c37379766b508a38b91afc68ec3be41bccf90b849b3bb0864702144c54ee6d63b0fa48667d3ea"
let pubKey = bytesFromHex(pubKeyHex)
let pubKeyB64 = base64.encode(bytesToStrPub(pubKey))

# --- 1. buildPublicKeyFromB64: round-trip the known key through base64
# encode/decode to prove the decode-and-classify path works (both the
# 97-byte-with-prefix branch and the 96-byte-bare branch).
block:
  let built = buildPublicKeyFromB64(pubKeyB64)
  assert built.isOk, "buildPublicKeyFromB64 (97-byte, standard b64) failed"
  assert built.value == pubKey
  echo "buildPublicKeyFromB64 (97-byte SEC1, standard base64): OK"

block:
  # bare 96-byte X||Y (drop the leading 0x04) must also decode, with the
  # prefix restored.
  var bare = newSeq[byte](96)
  for i in 0 ..< 96: bare[i] = pubKey[i + 1]
  let bareB64 = base64.encode(bytesToStrPub(bare))
  let built = buildPublicKeyFromB64(bareB64)
  assert built.isOk, "buildPublicKeyFromB64 (96-byte bare) failed"
  assert built.value == pubKey
  echo "buildPublicKeyFromB64 (96-byte bare X||Y, prefix restored): OK"

# --- 2. decodeHeaderGetX5u: synthesize a header with an embedded x5u
# (base64 of the real pubkey) and confirm extraction - this doesn't need
# a valid signature, it's purely the header-JSON-field-extraction step.
proc stripPad(s: string): string =
  result = s
  while result.len > 0 and result[result.len - 1] == '=':
    result.setLen(result.len - 1)

block:
  let noPad = stripPad(base64.encode("{\"alg\":\"ES384\",\"x5u\":\"" & pubKeyB64 & "\"}"))
  let x5u = decodeHeaderGetX5u(noPad)
  assert x5u.isOk, "decodeHeaderGetX5u failed"
  assert x5u.value == pubKeyB64
  echo "decodeHeaderGetX5u: OK"

  let missing = decodeHeaderGetX5u(stripPad(base64.encode("{\"alg\":\"ES384\"}")))
  assert (not missing.isOk) and missing.error.kind == aekMissingX5U
  echo "decodeHeaderGetX5u correctly rejects a header with no x5u: OK"

# --- 3. verifyOidcTokenSelfSigned, x5u-driven: build a token whose header
# carries the same known-good pubkey as its x5u. Reusing the real ES384
# signature bytes here is NOT possible - changing the header invalidates
# the signature, since r/s cover header||payload - so this proves the x5u
# extraction -> buildPublicKeyFromB64 -> verify wiring reaches the crypto
# layer and that the crypto layer correctly rejects a header/signature
# mismatch, while step 4 proves the crypto layer itself passes on a real
# vector via the lower-level (non-x5u) path.
block:
  let noPad = stripPad(base64.encode("{\"alg\":\"ES384\",\"x5u\":\"" & pubKeyB64 & "\"}"))
  var parts: seq[string] = @[]
  var cur = ""
  for c in token:
    if c == '.':
      parts.add(cur)
      cur = ""
    else:
      cur.add(c)
  parts.add(cur)
  let forgedToken = noPad & "." & parts[1] & "." & parts[2]
  let res = verifyOidcTokenSelfSigned(forgedToken)
  assert (not res.isOk) and res.error.kind == aekInvalidSignature,
    "expected forged-header token to fail signature check"
  echo "verifyOidcTokenSelfSigned correctly rejects a header/signature mismatch: OK"

# --- 4. verifyEs384Token, positive case: the real, UNMODIFIED token and
# its real pubkey (no x5u involved - this proves the actual signature-
# verify + payload-decode wiring: base64url decode -> sha384 -> ecdsa
# P-384 verify via ../jwt -> JSON payload decode, end to end).
block:
  let res = verifyEs384Token(token, pubKey)
  assert res.isOk, "expected the real ES384 token to verify successfully"
  echo "verifyEs384Token (real, unmodified ES384 token + pubkey): OK"

  # tamper with one payload char - must now fail
  var tampered = token
  var flipped = false
  var dots = 0
  var out2 = ""
  for c in tampered:
    if c == '.':
      inc dots
      out2.add(c)
    elif dots == 1 and not flipped:
      out2.add(if c == 'A': 'B' else: 'A')
      flipped = true
    else:
      out2.add(c)
  let tamperedRes = verifyEs384Token(out2, pubKey)
  assert not tamperedRes.isOk, "tampered token should have failed verification"
  echo "verifyEs384Token correctly rejects a tampered payload: OK"

echo "all jwt.nim integration checks passed"
