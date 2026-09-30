## The server's network-transport entrypoint.
##
## This is ONE of two ways to reach a `ServerCore` (see
## `src/server/servercore.nim`'s header comment for the full split
## rationale): this file owns a real TCP listener and the Java-edition
## wire framing (`src/protocol`), decodes what it reads, and forwards it
## into a `ServerCore`. It contains NO server logic of its own - any real
## behavior belongs in `ServerCore` or something it owns.
##
## The other way in is `startEmbeddedServer()` (in `server/servercore.nim`),
## for an in-process host (Jester) that wants direct calls instead of
## looping packets through a socket even on localhost.
##
## Scope of what's wired up here: a real accepting TCP listener on the
## configured port that correctly speaks the handshake + status
## (server-list-ping) sub-protocol end to end - enough that a real
## Minecraft client's server list shows this server, its MOTD, and
## responds to ping/pong for latency - proving the listener, the framing
## codec, and `ServerCore` are for-real wired together. Login/play-state
## packet dispatch (the ~19.5k-line `net/` surface upstream) is NOT
## implemented yet; a login attempt gets a clean disconnect, not a silent
## hang or a crash.
##
## No `raise`/exceptions anywhere in this file, matching every other
## fallible-I/O boundary in this port (see e.g. `nbtbase.nim`'s header):
## socket reads return a `(ok: bool, ...)` shape the caller checks
## explicitly instead.

import std/syncio
import protocol/varint
import protocol/netcodec
import protocol/protobase
import server/servercore
import server/net/winsock

proc appendSeq(dst: var seq[byte], src: seq[byte]) =
  for b in src:
    dst.add(b)

const DefaultPort = 25565'u16

# --- minimal packet framing over a live socket ------------------------

proc readVarIntFromSocket(sock: SocketHandle): tuple[ok: bool, value: VarInt] =
  ## Reads a Java-edition VarInt directly off the wire, one byte at a
  ## time (can't use varint.nim's buffer-based decoder until we know how
  ## many bytes the value takes).
  var value: uint32 = 0
  var shift = 0
  while true:
    let b = recvByte(sock)
    if b < 0:
      return (ok: false, value: newVarInt(0'i32))
    let byteVal = uint8(b)
    value = value or (uint32(byteVal and 0x7F'u8) shl shift)
    if (byteVal and 0x80'u8) == 0:
      break
    shift += 7
    if shift >= 32:
      return (ok: false, value: newVarInt(0'i32))
  (ok: true, value: newVarInt(cast[int32](value)))

proc readExact(sock: SocketHandle, n: int): tuple[ok: bool, data: seq[byte]] =
  var buf = newSeq[byte](n)
  if n == 0:
    return (ok: true, data: buf)
  var got = 0
  while got < n:
    let r = recvInto(sock, buf, n) # single-shot recv; MC handshake packets are tiny (fit one TCP segment)
    if r <= 0:
      return (ok: false, data: buf)
    got += r
    if got < n:
      return (ok: false, data: buf) # fragmented handshake packet - not supported yet
  (ok: true, data: buf)

proc readPacket(sock: SocketHandle): tuple[ok: bool, id: int32, body: seq[byte]] =
  let lenVi = readVarIntFromSocket(sock)
  if not lenVi.ok:
    return (ok: false, id: 0'i32, body: newSeq[byte](0))
  let total = int(lenVi.value.value)
  let raw = readExact(sock, total)
  if not raw.ok:
    return (ok: false, id: 0'i32, body: newSeq[byte](0))
  var pos = 0
  let idRes = decodeJava(raw.data, pos)
  if not idRes.isOk:
    return (ok: false, id: 0'i32, body: newSeq[byte](0))
  (ok: true, id: idRes.value.value, body: raw.data[pos ..< raw.data.len])

proc sendPacket(sock: SocketHandle, id: int32, bodyWriter: var NetWriter): bool =
  var idBuf: seq[byte] = @[]
  encodeJava(newVarInt(id), idBuf)
  var full: seq[byte] = @[]
  appendSeq(full, idBuf)
  appendSeq(full, bodyWriter.buf)
  var lenBuf: seq[byte] = @[]
  encodeJava(newVarInt(int32(full.len)), lenBuf)
  var outBuf: seq[byte] = @[]
  appendSeq(outBuf, lenBuf)
  appendSeq(outBuf, full)
  sendAll(sock, outBuf)

# --- handshake + status sub-protocol -----------------------------------

proc jsonEscape(s: string): string =
  ## Minimal `"` escaping - avoids pulling in `std/strutils` (`.replace`)
  ## purely to dodge that import's current Nimony-compiler crash (see
  ## NIMONY-COMPILER-BUGS.md); the MOTD is the only free-text field here.
  result = ""
  for ch in s:
    if ch == '"':
      result.add('\\')
    result.add(ch)

proc statusResponseJson(core: ServerCore): string =
  ## Hand-built JSON (no generic JSON encoder needed for this fixed
  ## shape) matching the vanilla status response schema closely enough
  ## for a real client's server list to render it.
  "{\"version\":{\"name\":\"Nimony 1.21.11\",\"protocol\":768}," &
  "\"players\":{\"max\":20,\"online\":" & $core.playerCount() & ",\"sample\":[]}," &
  "\"description\":{\"text\":\"" & jsonEscape(core.motd) & "\"}}"

proc handleStatus(sock: SocketHandle, core: ServerCore) =
  while true:
    let pkt = readPacket(sock)
    if not pkt.ok:
      return
    case pkt.id
    of 0: # status request (empty body) -> status response
      var w = newNetWriter()
      discard writeString(w, statusResponseJson(core))
      if not sendPacket(sock, 0, w):
        return
    of 1: # ping request -> pong (echo the i64 payload)
      var r = newNetReader(pkt.body)
      let payload = getI64Be(r)
      var w = newNetWriter()
      if payload.isOk:
        writeI64Be(w, payload.value)
      discard sendPacket(sock, 1, w)
      return
    else:
      return

proc handleLogin(sock: SocketHandle, core: ServerCore, protocolVersion: int32) =
  ## Full login-state packet dispatch (encryption, compression, profile
  ## resolution, join-game, then the play-state packet surface) isn't
  ## implemented yet - see this file's header comment. Send a clean,
  ## honest disconnect instead of hanging the connection or crashing.
  discard protocolVersion
  discard core
  var w = newNetWriter()
  discard writeString(w, "{\"text\":\"This Nimony server only implements status ping so far - login/play is not wired up yet.\"}")
  discard sendPacket(sock, 0, w) # CLoginDisconnect packet id 0x00

proc handleConnection(sock: SocketHandle, core: ServerCore) =
  let pkt = readPacket(sock)
  if pkt.ok and pkt.id == 0:
    var r = newNetReader(pkt.body)
    let protoVer = getVarInt(r)
    let hostAddr = getStr(r)
    discard hostAddr
    let p0 = getU8(r)
    let p1 = getU8(r)
    discard p0
    discard p1
    let nextState = getVarInt(r)
    if protoVer.isOk and nextState.isOk:
      case nextState.value.value
      of 1: handleStatus(sock, core)
      of 2: handleLogin(sock, core, protoVer.value.value)
      else: discard
  closeClient(sock)

proc runListener*(core: ServerCore, port: uint16 = DefaultPort): bool =
  ## Returns false if the listener could not be started at all (Winsock
  ## init or bind/listen failure) - never returns true, since the accept
  ## loop below only exits on that kind of startup failure.
  if not initWinsock():
    echo "FATAL: WSAStartup failed"
    return false
  let listener = listenOn(port)
  if int(listener) == int(InvalidSocket):
    echo "FATAL: could not bind/listen on port " & $port & " (already in use?)"
    return false
  echo "Nimony Minecraft server listening on port " & $port & " (" & core.motd & ")"
  echo "Status/ping is wired up; login/play packet dispatch is not implemented yet."
  while true:
    let client = acceptClient(listener)
    if int(client) != int(InvalidSocket):
      handleConnection(client, core)

when isMainModule:
  let core = newServerCore(motd = "A Nimony Minecraft Server (port in progress)")
  discard runListener(core)
