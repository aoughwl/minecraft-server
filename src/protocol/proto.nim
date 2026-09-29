## Top-level protocol constants and shared types.
## Port of the non-async, non-encryption-stream parts of
## upstream/protocol/src/lib.rs.
##
## NOT ported: `StreamDecryptor`/`StreamEncryptor` (AES-128-CFB8 login
## encryption over an `AsyncRead`/`AsyncWrite` - tokio-specific async I/O
## with no Nimony equivalent yet; the crypto primitive itself would reuse
## this port's sibling `jwt` library's approach once ported) and the
## `ClientPacket`/`ServerPacket`/`BClientPacket` traits (Nimony has no
## traits; each concrete packet type will just expose its own
## `writePacketData`/`readPacketData` procs directly, the way
## `src/nbt/tag.nim`'s `serializeData`/`deserializeDataDepth` do).

import protobase, netcodec, varint

const
  MaxPacketSize* = 2_097_152'u64
  MaxPacketDataSize* = 8_388_608

type
  ConnectionState* = enum
    csHandShake
    csStatus
    csLogin
    csTransfer
    csConfig
    csPlay

proc connectionStateFromVarInt*(value: int32): (bool, ConnectionState) =
  ## Port of `TryFrom<VarInt> for ConnectionState`. Returns
  ## `(false, csHandShake)` for `InvalidConnectionState`, matching the
  ## house `(bool, T)` convention for a simple fallible conversion.
  case value
  of 1: (true, csStatus)
  of 2: (true, csLogin)
  of 3: (true, csTransfer)
  else: (false, csHandShake)

type
  IdOrKind* = enum
    iokId
    iokValue

  IdOr*[T] = object
    case kind*: IdOrKind
    of iokId: id*: uint16
    of iokValue: value*: T

  RawPacket* = object
    id*: int32
    payload*: seq[byte]

proc readIdOr*[T](r: var NetReader, readValue: proc(r: var NetReader): ProtoReadResult[T] {.closure.}): ProtoReadResult[IdOr[T]] =
  let idR = getVarInt(r)
  if not idR.isOk:
    return readErr[IdOr[T]](idR.error)
  if idR.value.value == 0:
    let v = readValue(r)
    if not v.isOk:
      return readErr[IdOr[T]](v.error)
    readOk[IdOr[T]](IdOr[T](kind: iokValue, value: v.value))
  else:
    readOk[IdOr[T]](IdOr[T](kind: iokId, id: uint16(idR.value.value - 1)))

proc writeIdOr*[T](v: IdOr[T], w: var NetWriter, writeValue: proc(w: var NetWriter, val: T) {.closure.}) =
  case v.kind
  of iokId:
    writeVarInt(w, newVarInt(int32(v.id) + 1))
  of iokValue:
    writeVarInt(w, newVarInt(0))
    writeValue(w, v.value)
