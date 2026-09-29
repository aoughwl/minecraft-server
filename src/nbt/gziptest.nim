## Round-trip smoke test for gzip-compressed NBT (nbt_compress.nim), run
## via `nimony c -r src/nbt/gziptest.nim`. Proves real compress/decompress
## through the system zlib, not just that the code compiles.

import std/syncio
import std/assertions
import tag, nbtbase, nbt_compress

proc buildSample(): NbtCompound =
  var c = newCompound()
  put(c, "byte_value", NbtTag(kind: ntkByte, byteVal: 123))
  put(c, "int_value", NbtTag(kind: ntkInt, intVal: 1234567))
  put(c, "string_value", NbtTag(kind: ntkString, stringVal: "test string"))
  var nested = newCompound()
  put(nested, "nested_int", NbtTag(kind: ntkInt, intVal: 42))
  put(c, "nested_compound", NbtTag(kind: ntkCompound, compoundVal: nested))
  c

let sample = buildSample()
let writeRes = writeGzipCompoundTag(sample)
assert writeRes.isOk, "gzip compress failed"
echo "compressed to " & $writeRes.value.len & " bytes"
assert writeRes.value.len >= 2, "suspiciously small gzip output"
assert writeRes.value[0] == 0x1f'u8 and writeRes.value[1] == 0x8b'u8, "missing gzip magic bytes"

let readRes = readGzipCompoundTag(writeRes.value)
assert readRes.isOk, "gzip decompress failed"

let (foundByte, byteTag) = get(readRes.value, "byte_value")
assert foundByte and byteTag.kind == ntkByte and byteTag.byteVal == 123
let (foundStr, strTag) = get(readRes.value, "string_value")
assert foundStr and strTag.kind == ntkString and strTag.stringVal == "test string"
let (foundNested, nestedTag) = get(readRes.value, "nested_compound")
assert foundNested and nestedTag.kind == ntkCompound
let (foundNestedInt, nestedIntTag) = get(nestedTag.compoundVal, "nested_int")
assert foundNestedInt and nestedIntTag.intVal == 42

echo "gzip NBT round-trip: OK"
