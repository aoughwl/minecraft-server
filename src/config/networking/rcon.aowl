## Port of upstream/config/src/networking/rcon.rs

import netaddr

type
  RconLogging* = object
    loggedSuccessfully*: bool
    wrongPassword*: bool
    commands*: bool
    quit*: bool

  RconConfig* = object
    enabled*: bool
    address*: SocketAddr
    password*: string
    maxConnections*: uint32
    logging*: RconLogging

proc defaultRconLogging*(): RconLogging =
  RconLogging(loggedSuccessfully: true, wrongPassword: true, commands: true, quit: true)

proc defaultRconConfig*(): RconConfig =
  RconConfig(
    enabled: false,
    address: unspecified(25575'u16),
    password: "",
    maxConnections: 10'u32,
    logging: defaultRconLogging(),
  )
