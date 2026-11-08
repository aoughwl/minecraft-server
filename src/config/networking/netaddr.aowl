## Minimal stand-in for Rust's `std::net::SocketAddr`, used by config structs
## that just need to store a bind address (query.rs, rcon.rs). No real
## networking module exists yet in this port; this is deliberately just
## enough shape to hold `ip:port` defaults. TODO: replace with a proper
## socket-address type (v4/v6, parsing, display) once the networking layer
## is being ported.

type
  SocketAddr* = object
    ip*: array[4, byte]   ## IPv4 only for now.
    port*: uint16

proc unspecified*(port: uint16): SocketAddr {.inline.} =
  SocketAddr(ip: [0'u8, 0, 0, 0], port: port)
