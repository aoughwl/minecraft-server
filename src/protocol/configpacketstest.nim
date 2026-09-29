## Round-trip test for configpackets.nim, run via `nimony c -r`.
import std/assertions
import std/syncio
import protobase, netcodec, configpackets

proc roundtrip(p: CRegistryData) =
  var w = newNetWriter()
  let wr = writePacketData(p, w)
  assert wr.isOk, "write failed"
  var r = newNetReader(w.buf)
  let rr = readPacketData(CRegistryData, r)
  assert rr.isOk, "read failed"
  let got = rr.value
  assert got.registryId == p.registryId
  assert got.entries.len == p.entries.len
  for i in 0 ..< p.entries.len:
    assert got.entries[i].entryId == p.entries[i].entryId
    assert got.entries[i].hasData == p.entries[i].hasData
    assert got.entries[i].data == p.entries[i].data

# One entry with a data blob (the real upstream usage shape).
roundtrip(CRegistryData(
  registryId: "minecraft:worldgen/biome",
  entries: @[
    RegistryEntryData(entryId: "minecraft:plains", hasData: true, data: @[10'u8, 0, 0, 0]),
  ]
))

# Entries with no override data.
roundtrip(CRegistryData(
  registryId: "minecraft:dimension_type",
  entries: @[
    RegistryEntryData(entryId: "minecraft:overworld", hasData: false, data: @[]),
  ]
))

echo "configpackets round-trip: OK"
