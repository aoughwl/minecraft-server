## Minimal raw Winsock2 FFI.
##
## Nimony's `std/nativesocket.nim` is type scaffolding only - no actual
## `socket`/`bind`/`listen`/`accept`/`send`/`recv` syscalls are wired up
## (confirmed by reading it: just `Port`/`Domain`/`SockType`/`Protocol`
## enums, nothing else), and `std/net` doesn't exist in Nimony's lib at
## all (`file not found: std\net.nim`). Real listening sockets therefore
## need direct C FFI. This is scoped to exactly what `src/main.nim` needs
## for a real accept/recv/send loop on Windows (this port's only dev
## target so far) - not a portable sockets abstraction. A POSIX variant
## (`<sys/socket.h>`) would be a straightforward sibling file if/when this
## ports to Linux, following the same split `src/nbt/nbt_compress.nim`
## already documents for its own platform-specific gap.
##
## No `raise`/exceptions anywhere in this file - Nimony has no
## Nim-compatible exception mechanism (see nbtbase.nim's header for the
## house explanation), so every fallible proc here returns a plain `bool`/
## sentinel `int` instead, matching this port's `XResult`-free, simplest-
## possible convention for FFI wrappers this thin.

const Ws2_32 = "ws2_32.dll"

type
  WSAData = object
    ## Matches the real `WSADATA` layout closely enough: this code never
    ## reads its fields, only passes a big-enough buffer for WSAStartup
    ## to fill in, so padding it generously (real struct is ~400 bytes on
    ## Win64) is sufficient without reproducing every field.
    raw: array[512, byte]

  SocketHandle* = distinct int

  SockAddrIn = object
    ## Matches the real `struct sockaddr_in` layout (Win32/Win64: no
    ## padding differences for this shape).
    sin_family: int16
    sin_port: uint16
    sin_addr: uint32
    sin_zero: array[8, byte]

const
  AfInet = cint(2)
  SockStream = cint(1)
  IpprotoTcp = cint(6)
  InvalidSocket* = SocketHandle(-1)
  SocketErrorC = cint(-1)
  SolSocket = cint(0xFFFF)
  SoReuseAddr = cint(4)

proc wsaStartup(wVersionRequested: uint16, lpWSAData: ptr WSAData): cint
  {.stdcall, importc: "WSAStartup", dynlib: Ws2_32.}

proc wsaCleanup(): cint {.stdcall, importc: "WSACleanup", dynlib: Ws2_32.}

proc cSocket(domain, typ, protocol: cint): SocketHandle
  {.stdcall, importc: "socket", dynlib: Ws2_32.}

proc cBind(s: SocketHandle, name: ptr SockAddrIn, namelen: cint): cint
  {.stdcall, importc: "bind", dynlib: Ws2_32.}

proc cListen(s: SocketHandle, backlog: cint): cint
  {.stdcall, importc: "listen", dynlib: Ws2_32.}

proc cAccept(s: SocketHandle, address: pointer, addrlen: pointer): SocketHandle
  {.stdcall, importc: "accept", dynlib: Ws2_32.}

proc cRecv(s: SocketHandle, buf: pointer, len: cint, flags: cint): cint
  {.stdcall, importc: "recv", dynlib: Ws2_32.}

proc cSend(s: SocketHandle, buf: pointer, len: cint, flags: cint): cint
  {.stdcall, importc: "send", dynlib: Ws2_32.}

proc cCloseSocket(s: SocketHandle): cint
  {.stdcall, importc: "closesocket", dynlib: Ws2_32.}

proc htons(hostshort: uint16): uint16 {.stdcall, importc: "htons", dynlib: Ws2_32.}

proc setsockoptInt(s: SocketHandle, level, optname: cint, optval: ptr cint, optlen: cint): cint
  {.stdcall, importc: "setsockopt", dynlib: Ws2_32.}

proc initWinsock*(): bool =
  ## false means WSAStartup failed - caller should bail out, there's no
  ## socket API to use at all.
  var wsa: WSAData = WSAData()
  let r = wsaStartup(uint16(0x0202), addr wsa) # MAKEWORD(2,2)
  r == 0

proc shutdownWinsock*() =
  discard wsaCleanup()

proc listenOn*(port: uint16, backlog: cint = cint(128)): SocketHandle =
  ## Returns `InvalidSocket` on any failure (socket/bind/listen) - caller
  ## checks with `int(result) == int(InvalidSocket)`.
  result = cSocket(AfInet, SockStream, IpprotoTcp)
  if int(result) == int(InvalidSocket):
    return InvalidSocket
  var reuse: cint = cint(1)
  discard setsockoptInt(result, SolSocket, SoReuseAddr, addr reuse, cint(sizeof(cint)))
  var addr4: SockAddrIn = SockAddrIn()
  addr4.sin_family = int16(AfInet)
  addr4.sin_port = htons(port)
  addr4.sin_addr = 0'u32 # INADDR_ANY
  let bindRes = cBind(result, addr addr4, cint(sizeof(SockAddrIn)))
  if bindRes == SocketErrorC:
    discard cCloseSocket(result)
    return InvalidSocket
  let listenRes = cListen(result, backlog)
  if listenRes == SocketErrorC:
    discard cCloseSocket(result)
    return InvalidSocket

proc acceptClient*(listener: SocketHandle): SocketHandle =
  ## Returns `InvalidSocket` on failure.
  cAccept(listener, cast[pointer](0), cast[pointer](0))

proc recvByte*(s: SocketHandle): int =
  ## Returns the byte read (0..255), or -1 on orderly close/error.
  var b: byte = 0'u8
  let n = cRecv(s, addr b, cint(1), cint(0))
  if n != cint(1):
    return -1
  int(b)

proc recvInto*(s: SocketHandle, buf: var seq[byte], count: int): int =
  ## Reads up to `count` bytes into `buf[0..<count]`. Returns bytes read
  ## (0 means orderly close), <0 on error.
  if count == 0:
    return 0
  int(cRecv(s, addr buf[0], cint(count), cint(0)))

proc sendAll*(s: SocketHandle, data: seq[byte]): bool =
  ## Returns false if `send()` failed partway through.
  if data.len == 0:
    return true
  var sent = 0
  while sent < data.len:
    let n = cSend(s, unsafeAddr data[sent], cint(data.len - sent), cint(0))
    if n <= cint(0):
      return false
    sent += int(n)
  true

proc closeClient*(s: SocketHandle) =
  discard cCloseSocket(s)
