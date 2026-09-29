## Smoke test for netcodec.nim's read/write primitives: writes a value with
## each NetWriter proc, reads it back with the matching NetReader proc,
## and checks round-trip equality. Run with `nimony c -r`.

import std/assertions
import std/syncio
import netcodec, varint, protobase

var w = newNetWriter()
writeU8(w, 0xAB'u8)
writeI8(w, -5'i8)
writeI16Be(w, -1234'i16)
writeU16Be(w, 54321'u16)
writeI32Be(w, -70000'i32)
writeU32Be(w, 4_000_000_000'u32)
writeI64Be(w, -123456789012345'i64)
writeU64Be(w, 18_000_000_000_000_000_000'u64)
writeF32Be(w, 3.5'f32)
writeF64Be(w, 2.71828)
writeBool(w, true)
writeBool(w, false)
writeVarInt(w, newVarInt(-999999'i32))
let sr = writeString(w, "hello é中\U0001F600")
assert sr.isOk

var r = newNetReader(w.buf)
assert getU8(r).value == 0xAB'u8
assert getI8(r).value == -5'i8
assert getI16Be(r).value == -1234'i16
assert getU16Be(r).value == 54321'u16
assert getI32Be(r).value == -70000'i32
assert getU32Be(r).value == 4_000_000_000'u32
assert getI64Be(r).value == -123456789012345'i64
assert getU64Be(r).value == 18_000_000_000_000_000_000'u64
assert getF32Be(r).value == 3.5'f32
assert getF64Be(r).value == 2.71828
assert getBool(r).value == true
assert getBool(r).value == false
let vi = getVarInt(r)
assert vi.isOk
assert vi.value.value == -999999'i32
let strR = getStr(r)
assert strR.isOk
assert strR.value == "hello é中\U0001F600"

echo "all netcodec checks passed"
