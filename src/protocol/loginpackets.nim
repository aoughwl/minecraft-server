## Concrete Java-edition login/configuration-state packet types.
## Port of a handful of upstream/protocol/src/java/{client,server}/
## {login,config}/*.rs files - the smaller, foundational, non-version-
## branching packets, picked to exercise the framing layer
## (netcodec.nim/varint.nim/protobase.nim) with real packet shapes before
## tackling the larger play-state packets.
##
## Upstream's `ClientPacket`/`ServerPacket` traits don't exist here
## (Nimony has no traits, per proto.nim's header note); each packet type
## below just exposes its own `writePacketData`/`readPacketData` procs
## directly, the same shape src/nbt/tag.nim's serialize/deserialize use.
##
## Multi-version field gating (`JavaMinecraftVersion` branches upstream)
## is NOT reproduced - these are ported against the current/latest wire
## shape only. A real multi-version story needs `pumpkin_util::version`
## ported first; TODO once that's in place.

import protobase, netcodec, varint

# --- CSetCompression / login_compression -----------------------------------

type
  CSetCompression* = object
    threshold*: VarInt

proc writePacketData*(p: CSetCompression, w: var NetWriter) =
  writeVarInt(w, p.threshold)

proc readPacketData*(_: typedesc[CSetCompression], r: var NetReader): ProtoReadResult[CSetCompression] =
  let t = getVarInt(r)
  if not t.isOk:
    return readErr[CSetCompression](t.error)
  readOk[CSetCompression](CSetCompression(threshold: t.value))

# --- CLoginDisconnect --------------------------------------------------

type
  CLoginDisconnect* = object
    jsonReason*: string

proc writePacketData*(p: CLoginDisconnect, w: var NetWriter): ProtoWriteVoidResult =
  writeString(w, p.jsonReason)

proc readPacketData*(_: typedesc[CLoginDisconnect], r: var NetReader): ProtoReadResult[CLoginDisconnect] =
  let s = getStr(r)
  if not s.isOk:
    return readErr[CLoginDisconnect](s.error)
  readOk[CLoginDisconnect](CLoginDisconnect(jsonReason: s.value))

# --- SKeepAlive (config-state serverbound keep-alive reply) -----------------

type
  SKeepAlive* = object
    keepAliveId*: int64

proc writePacketData*(p: SKeepAlive, w: var NetWriter) =
  writeI64Be(w, p.keepAliveId)

proc readPacketData*(_: typedesc[SKeepAlive], r: var NetReader): ProtoReadResult[SKeepAlive] =
  let v = getI64Be(r)
  if not v.isOk:
    return readErr[SKeepAlive](v.error)
  readOk[SKeepAlive](SKeepAlive(keepAliveId: v.value))

# --- SConfigPong ---------------------------------------------------------

type
  SConfigPong* = object
    id*: int32

proc writePacketData*(p: SConfigPong, w: var NetWriter) =
  writeI32Be(w, p.id)

proc readPacketData*(_: typedesc[SConfigPong], r: var NetReader): ProtoReadResult[SConfigPong] =
  let v = getI32Be(r)
  if not v.isOk:
    return readErr[SConfigPong](v.error)
  readOk[SConfigPong](SConfigPong(id: v.value))

# --- CFinishConfig / SAcknowledgeFinishConfig (empty-body packets) ---------

type
  CFinishConfig* = object
  SAcknowledgeFinishConfig* = object

proc writePacketData*(p: CFinishConfig, w: var NetWriter) = discard
proc readPacketData*(_: typedesc[CFinishConfig], r: var NetReader): ProtoReadResult[CFinishConfig] =
  readOk[CFinishConfig](CFinishConfig())

proc writePacketData*(p: SAcknowledgeFinishConfig, w: var NetWriter) = discard
proc readPacketData*(_: typedesc[SAcknowledgeFinishConfig], r: var NetReader): ProtoReadResult[SAcknowledgeFinishConfig] =
  readOk[SAcknowledgeFinishConfig](SAcknowledgeFinishConfig())

# --- CLoginCookieRequest (clientbound only) --------------------------------
# `key` is upstream's `ResourceLocation` (util's port, e.g. "minecraft:foo");
# represented here as a plain wire-format string, since this packet only
# ever serializes it.

type
  CLoginCookieRequest* = object
    key*: string

proc writePacketData*(p: CLoginCookieRequest, w: var NetWriter): ProtoWriteVoidResult =
  writeString(w, p.key)

# --- SLoginCookieResponse (serverbound only) -------------------------------

const MaxCookieLength = 5120

type
  SLoginCookieResponse* = object
    key*: string
    hasPayload*: bool
    payload*: seq[byte]  ## meaningful only when hasPayload

proc writePacketData*(p: SLoginCookieResponse, w: var NetWriter): ProtoWriteVoidResult =
  let kr = writeString(w, p.key)
  if not kr.isOk:
    return kr
  if p.hasPayload:
    writeBool(w, true)
    writeVarInt(w, newVarInt(int32(p.payload.len)))
    writeSlice(w, p.payload)
  else:
    writeBool(w, false)
  writeOkVoid()

proc readPacketData*(_: typedesc[SLoginCookieResponse], r: var NetReader): ProtoReadResult[SLoginCookieResponse] =
  let keyR = getStr(r)
  if not keyR.isOk:
    return readErr[SLoginCookieResponse](keyR.error)
  let hasR = getBool(r)
  if not hasR.isOk:
    return readErr[SLoginCookieResponse](hasR.error)
  if not hasR.value:
    return readOk[SLoginCookieResponse](SLoginCookieResponse(key: keyR.value, hasPayload: false, payload: @[]))
  let lenR = getVarInt(r)
  if not lenR.isOk:
    return readErr[SLoginCookieResponse](lenR.error)
  let length = int(lenR.value.value)
  if length < 0 or length > MaxCookieLength:
    return readErr[SLoginCookieResponse](tooLarge("SLoginCookieResponse"))
  var payload = newSeq[byte](length)
  let br = readBytesToBuf(r, payload)
  if not br.isOk:
    return readErr[SLoginCookieResponse](br.error)
  readOk[SLoginCookieResponse](SLoginCookieResponse(key: keyR.value, hasPayload: true, payload: payload))

# --- SLoginPluginResponse ---------------------------------------------------
# `data`'s absence of a length prefix upstream (it's just "the rest of the
# packet") is reproduced by reading whatever remains in the reader's buffer.

type
  SLoginPluginResponse* = object
    messageId*: VarInt
    hasData*: bool
    data*: seq[byte]

proc writePacketData*(p: SLoginPluginResponse, w: var NetWriter) =
  writeVarInt(w, p.messageId)
  if p.hasData:
    writeBool(w, true)
    writeSlice(w, p.data)
  else:
    writeBool(w, false)

const MaxPluginPayloadSize = 1_048_576

proc readPacketData*(_: typedesc[SLoginPluginResponse], r: var NetReader): ProtoReadResult[SLoginPluginResponse] =
  let idR = getVarInt(r)
  if not idR.isOk:
    return readErr[SLoginPluginResponse](idR.error)
  let hasR = getBool(r)
  if not hasR.isOk:
    return readErr[SLoginPluginResponse](hasR.error)
  if not hasR.value:
    return readOk[SLoginPluginResponse](SLoginPluginResponse(messageId: idR.value, hasData: false, data: @[]))
  let remainingLen = r.data.len - r.pos
  if remainingLen > MaxPluginPayloadSize:
    return readErr[SLoginPluginResponse](tooLarge("SLoginPluginResponse"))
  var payload = newSeq[byte](remainingLen)
  let br = readBytesToBuf(r, payload)
  if not br.isOk:
    return readErr[SLoginPluginResponse](br.error)
  readOk[SLoginPluginResponse](SLoginPluginResponse(messageId: idR.value, hasData: true, data: payload))
