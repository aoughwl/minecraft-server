## More small Java-edition configuration-state packets, continuing
## configpackets.nim / loginpackets.nim's coverage.
## Port of upstream/protocol/src/java/client/config/{reset_chat,
## feature_flags,ping}.rs - picked for being small, single-direction or
## simple-bidirectional, and not needing the unported item/data-component
## machinery that blocks item_stack_seralizer.rs (see this crate's
## README.md entry for why that one's deferred).
##
## Multi-version field gating (`JavaMinecraftVersion`) is not reproduced,
## same caveat as loginpackets.nim.

import protobase, netcodec, varint

# --- CConfigResetChat (empty body) -----------------------------------------

type
  CConfigResetChat* = object

proc writePacketData*(p: CConfigResetChat, w: var NetWriter) =
  discard

proc readPacketData*(_: typedesc[CConfigResetChat], r: var NetReader): ProtoReadResult[CConfigResetChat] =
  readOk[CConfigResetChat](CConfigResetChat())

# --- CFeatureFlags -----------------------------------------------------

type
  CFeatureFlags* = object
    features*: seq[string]

proc writeFeatureStr(w: var NetWriter, s: string): ProtoWriteVoidResult =
  writeString(w, s)

proc writePacketData*(p: CFeatureFlags, w: var NetWriter): ProtoWriteVoidResult =
  writeListRes(w, p.features, writeFeatureStr)

proc readPacketData*(_: typedesc[CFeatureFlags], r: var NetReader): ProtoReadResult[CFeatureFlags] =
  let lenR = getVarInt(r)
  if not lenR.isOk:
    return readErr[CFeatureFlags](lenR.error)
  var features: seq[string] = @[]
  for i in 0 ..< int(lenR.value.value):
    let s = getStr(r)
    if not s.isOk:
      return readErr[CFeatureFlags](s.error)
    features.add(s.value)
  readOk[CFeatureFlags](CFeatureFlags(features: features))

# --- CConfigPing / SConfigPing (bidirectional: server can ping too) --------

type
  CConfigPing* = object
    id*: int32

proc writePacketData*(p: CConfigPing, w: var NetWriter) =
  writeI32Be(w, p.id)

proc readPacketData*(_: typedesc[CConfigPing], r: var NetReader): ProtoReadResult[CConfigPing] =
  let idR = getI32Be(r)
  if not idR.isOk:
    return readErr[CConfigPing](idR.error)
  readOk[CConfigPing](CConfigPing(id: idR.value))
