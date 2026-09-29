## Round-trip test for src/protocol/loginpackets.nim - actually run via
## `nimony c -r`, not just compile-checked.

import std/assertions
import std/syncio
import protobase, netcodec, varint, loginpackets

proc bytesOf(w: NetWriter): seq[byte] = w.buf

block setCompression:
  let p = CSetCompression(threshold: newVarInt(256))
  var w = newNetWriter()
  writePacketData(p, w)
  var r = newNetReader(bytesOf(w))
  let got = readPacketData(CSetCompression, r)
  assert got.isOk
  assert got.value.threshold.value == 256
  echo "CSetCompression: OK"

block loginDisconnect:
  let p = CLoginDisconnect(jsonReason: "{\"text\":\"kicked\"}")
  var w = newNetWriter()
  let wr = writePacketData(p, w)
  assert wr.isOk
  var r = newNetReader(bytesOf(w))
  let got = readPacketData(CLoginDisconnect, r)
  assert got.isOk
  assert got.value.jsonReason == p.jsonReason
  echo "CLoginDisconnect: OK"

block keepAlive:
  let p = SKeepAlive(keepAliveId: 123456789012345'i64)
  var w = newNetWriter()
  writePacketData(p, w)
  var r = newNetReader(bytesOf(w))
  let got = readPacketData(SKeepAlive, r)
  assert got.isOk
  assert got.value.keepAliveId == p.keepAliveId
  echo "SKeepAlive: OK"

block configPong:
  let p = SConfigPong(id: -42)
  var w = newNetWriter()
  writePacketData(p, w)
  var r = newNetReader(bytesOf(w))
  let got = readPacketData(SConfigPong, r)
  assert got.isOk
  assert got.value.id == p.id
  echo "SConfigPong: OK"

block finishConfig:
  let p = CFinishConfig()
  var w = newNetWriter()
  writePacketData(p, w)
  assert bytesOf(w).len == 0
  var r = newNetReader(bytesOf(w))
  let got = readPacketData(CFinishConfig, r)
  assert got.isOk
  echo "CFinishConfig: OK"

block ackFinishConfig:
  let p = SAcknowledgeFinishConfig()
  var w = newNetWriter()
  writePacketData(p, w)
  assert bytesOf(w).len == 0
  var r = newNetReader(bytesOf(w))
  let got = readPacketData(SAcknowledgeFinishConfig, r)
  assert got.isOk
  echo "SAcknowledgeFinishConfig: OK"

block cookieRequest:
  let p = CLoginCookieRequest(key: "minecraft:example")
  var w = newNetWriter()
  let wr = writePacketData(p, w)
  assert wr.isOk
  assert bytesOf(w).len > 0
  echo "CLoginCookieRequest: OK (write-only packet)"

block cookieResponseWithPayload:
  let p = SLoginCookieResponse(key: "minecraft:example", hasPayload: true, payload: @[1'u8, 2, 3, 4])
  var w = newNetWriter()
  let wr = writePacketData(p, w)
  assert wr.isOk
  var r = newNetReader(bytesOf(w))
  let got = readPacketData(SLoginCookieResponse, r)
  assert got.isOk
  assert got.value.key == p.key
  assert got.value.hasPayload
  assert got.value.payload == p.payload
  echo "SLoginCookieResponse (with payload): OK"

block cookieResponseNoPayload:
  let p = SLoginCookieResponse(key: "minecraft:none", hasPayload: false, payload: @[])
  var w = newNetWriter()
  let wr = writePacketData(p, w)
  assert wr.isOk
  var r = newNetReader(bytesOf(w))
  let got = readPacketData(SLoginCookieResponse, r)
  assert got.isOk
  assert not got.value.hasPayload
  echo "SLoginCookieResponse (no payload): OK"

block pluginResponseWithData:
  let p = SLoginPluginResponse(messageId: newVarInt(7), hasData: true, data: @[9'u8, 8, 7])
  var w = newNetWriter()
  writePacketData(p, w)
  var r = newNetReader(bytesOf(w))
  let got = readPacketData(SLoginPluginResponse, r)
  assert got.isOk
  assert got.value.messageId.value == 7
  assert got.value.hasData
  assert got.value.data == p.data
  echo "SLoginPluginResponse (with data): OK"

block pluginResponseNoData:
  let p = SLoginPluginResponse(messageId: newVarInt(8), hasData: false, data: @[])
  var w = newNetWriter()
  writePacketData(p, w)
  var r = newNetReader(bytesOf(w))
  let got = readPacketData(SLoginPluginResponse, r)
  assert got.isOk
  assert not got.value.hasData
  echo "SLoginPluginResponse (no data): OK"

echo "all login/config packet round-trip checks passed"
