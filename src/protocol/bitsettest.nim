## Verifies BitSet against upstream bit_set.rs's own #[cfg(test)] vectors.
## Run with `nimony c -r src/protocol/bitsettest.nim`.

import std/assertions
import std/syncio
import bitset, netcodec, protobase

block roundTripByteArray:
  var b = newBitSet()
  setBit(b, 0, true)
  setBit(b, 8, true)
  setBit(b, 70, true)

  var w = newNetWriter()
  let enc = encodeWithVersion(b, w, true)
  assert enc.isOk

  # upstream: [9, 0x01, 0x01, 0, 0, 0, 0, 0, 0, 0x40]
  let expected: seq[byte] = @[9'u8, 0x01, 0x01, 0, 0, 0, 0, 0, 0, 0x40]
  assert w.buf == expected

  var r = newNetReader(w.buf)
  let dec = decodeWithVersion(r, true)
  assert dec.isOk
  assert getBit(dec.value, 0)
  assert getBit(dec.value, 8)
  assert getBit(dec.value, 70)
  assert not getBit(dec.value, 1)

block emptyEncodesEmpty:
  let b = newBitSet()
  var w = newNetWriter()
  let enc = encodeWithVersion(b, w, true)
  assert enc.isOk
  assert w.buf == @[0'u8]

  var r = newNetReader(w.buf)
  let dec = decodeWithVersion(r, true)
  assert dec.isOk
  assert not getBit(dec.value, 0)

block preVersionStaysLongArray:
  let b = fromU64(1)
  var w = newNetWriter()
  let enc = encodeWithVersion(b, w, false)
  assert enc.isOk
  assert w.buf == @[1'u8, 0, 0, 0, 0, 0, 0, 0, 1]

block rejectsOutOfRangeLength:
  # Negative when read as a var int
  let negative: seq[byte] = @[0xFF'u8, 0xFF, 0xFF, 0xFF, 0x0F]
  for v26 in [true, false]:
    var r = newNetReader(negative)
    let dec = decodeWithVersion(r, v26)
    assert not dec.isOk
    assert dec.error.kind == reTooLarge

echo "all bitset checks passed"
