## Port of upstream/config/src/networking/lan_broadcast.rs

import std/options

type
  LanBroadcastConfig* = object
    enabled*: bool
    motd*: Option[string]
    port*: Option[uint16]

proc defaultLanBroadcastConfig*(): LanBroadcastConfig =
  LanBroadcastConfig(enabled: false, motd: none[string](), port: none[uint16]())
