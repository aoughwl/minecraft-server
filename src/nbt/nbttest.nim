## Ad-hoc round-trip smoke test for the NBT port, run manually with
## `nimony c -r src/nbt/nbttest.nim`. Not a proper test suite (no test
## runner wired up yet) - just enough to prove serialize -> deserialize is
## the identity for a representative tag tree before trusting the port.

import std/syncio
import std/assertions
import tag, serializer, deserializer, nbtbase

proc buildSample(): NbtTag =
  var c = newCompound()
  put(c, "byte", NbtTag(kind: ntkByte, byteVal: -12))
  put(c, "short", NbtTag(kind: ntkShort, shortVal: 1234))
  put(c, "int", NbtTag(kind: ntkInt, intVal: -70000))
  put(c, "long", NbtTag(kind: ntkLong, longVal: 123456789012345'i64))
  put(c, "float", NbtTag(kind: ntkFloat, floatVal: 3.5'f32))
  put(c, "double", NbtTag(kind: ntkDouble, doubleVal: 2.71828))
  put(c, "str", NbtTag(kind: ntkString, stringVal: "hello nimony"))
  put(c, "bytearr", NbtTag(kind: ntkByteArray, byteArrayVal: @[1'i8, 2, 3, -4]))
  put(c, "intarr", NbtTag(kind: ntkIntArray, intArrayVal: @[10'i32, -20, 30]))
  put(c, "longarr", NbtTag(kind: ntkLongArray, longArrayVal: @[1'i64, 2, 3]))
  var inner = newCompound()
  put(inner, "nested", NbtTag(kind: ntkString, stringVal: "yes"))
  put(c, "compound", NbtTag(kind: ntkCompound, compoundVal: inner))
  var list: seq[NbtTag] = @[
    NbtTag(kind: ntkInt, intVal: 1),
    NbtTag(kind: ntkInt, intVal: 2),
    NbtTag(kind: ntkInt, intVal: 3),
  ]
  put(c, "list", NbtTag(kind: ntkList, listVal: list))
  NbtTag(kind: ntkCompound, compoundVal: c)

proc runMode(mode: NbtWriteMode, readMode: NbtReadMode, label: string) =
  let sample = buildSample()
  var w = newNbtWriter(mode)
  let wr = serialize(sample, w)
  assert wr.isOk, label & ": serialize failed"

  var r = newNbtReader(readMode, w.buf)
  let rr = deserialize(r)
  assert rr.isOk, label & ": deserialize failed"

  var w2 = newNbtWriter(mode)
  let wr2 = serialize(rr.value, w2)
  assert wr2.isOk, label & ": re-serialize failed"
  assert w2.buf == w.buf, label & ": round-trip bytes differ"
  echo label & ": OK (" & $w.buf.len & " bytes)"

runMode(nwmJava, nrmJava, "java")
runMode(nwmBedrock, nrmBedrock, "bedrock")
echo "all nbt round-trip checks passed"
