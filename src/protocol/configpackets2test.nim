## Round-trip test for configpackets2.nim, run via `nimony c -r`.
import std/assertions
import std/syncio
import protobase, netcodec, configpackets2

block resetChat:
  var w = newNetWriter()
  writePacketData(CConfigResetChat(), w)
  var r = newNetReader(w.buf)
  let rr = readPacketData(CConfigResetChat, r)
  assert rr.isOk
  assert w.buf.len == 0

block featureFlags:
  let p = CFeatureFlags(features: @["minecraft:vanilla", "minecraft:bundle", "minecraft:trade_rebalance"])
  var w = newNetWriter()
  let wr = writePacketData(p, w)
  assert wr.isOk
  var r = newNetReader(w.buf)
  let rr = readPacketData(CFeatureFlags, r)
  assert rr.isOk
  assert rr.value.features == p.features

block emptyFeatureFlags:
  let p = CFeatureFlags(features: @[])
  var w = newNetWriter()
  let wr = writePacketData(p, w)
  assert wr.isOk
  var r = newNetReader(w.buf)
  let rr = readPacketData(CFeatureFlags, r)
  assert rr.isOk
  assert rr.value.features.len == 0

block ping:
  for testId in [0'i32, 1, -1, 2147483647'i32, -2147483648'i32]:
    let p = CConfigPing(id: testId)
    var w = newNetWriter()
    writePacketData(p, w)
    var r = newNetReader(w.buf)
    let rr = readPacketData(CConfigPing, r)
    assert rr.isOk
    assert rr.value.id == testId

echo "configpackets2 round-trip: OK"
