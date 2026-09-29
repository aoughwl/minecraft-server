## Round-trip / known-vector smoke test for varint.nim, checked against
## pumpkin-protocol/src/codec/var_int.rs's own #[cfg(test)] vectors.
## Run manually with `nimony c -r src/protocol/varinttest.nim`.

import std/assertions
import std/syncio
import protobase, varint

proc roundTripJava(v: int32) =
  var buf: seq[byte] = @[]
  encodeJava(VarInt(value: v), buf)
  var pos = 0
  let r = decodeJava(buf, pos)
  assert r.isOk, "java decode failed for " & $v
  assert r.value.value == v, "java round-trip mismatch for " & $v
  assert pos == buf.len, "java decode didn't consume whole buffer for " & $v

proc roundTripBedrock(v: int32) =
  var buf: seq[byte] = @[]
  encodeBedrock(VarInt(value: v), buf)
  var pos = 0
  let r = decodeBedrock(buf, pos)
  assert r.isOk, "bedrock decode failed for " & $v
  assert r.value.value == v, "bedrock round-trip mismatch for " & $v

for v in [int32.low, -2'i32, -1'i32, 0'i32, 1'i32, 2'i32, int32.high]:
  roundTripJava(v)
  roundTripBedrock(v)

block:
  # accepts_boundary_values (Java)
  var pos = 0
  let r0 = decodeJava(@[0x00'u8], pos)
  assert r0.isOk and r0.value.value == 0

  pos = 0
  let rNeg1 = decodeJava(@[0xFF'u8, 0xFF, 0xFF, 0xFF, 0x0F], pos)
  assert rNeg1.isOk and rNeg1.value.value == -1

  pos = 0
  let rMax = decodeJava(@[0xFF'u8, 0xFF, 0xFF, 0xFF, 0x07], pos)
  assert rMax.isOk and rMax.value.value == int32.high

block:
  # rejects_overflowing_final_byte (Java)
  var pos = 0
  let r1 = decodeJava(@[0x80'u8, 0x80, 0x80, 0x80, 0x10], pos)
  assert not r1.isOk

  pos = 0
  let r2 = decodeJava(@[0xFF'u8, 0xFF, 0xFF, 0xFF, 0x7F], pos)
  assert not r2.isOk

block:
  # packet_read_rejects_overflowing_final_byte (Bedrock)
  var pos = 0
  let r1 = decodeBedrock(@[0x80'u8, 0x80, 0x80, 0x80, 0x10], pos)
  assert not r1.isOk

  pos = 0
  let r2 = decodeBedrock(@[0x01'u8], pos)
  assert r2.isOk and r2.value.value == -1

  pos = 0
  let r3 = decodeBedrock(@[0xFF'u8, 0xFF, 0xFF, 0xFF, 0x0F], pos)
  assert r3.isOk and r3.value.value == int32.low

echo "all varint checks passed"
