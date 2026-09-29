## Port of upstream/config/src/networking/query.rs

import netaddr

type
  QueryConfig* = object
    enabled*: bool
    address*: SocketAddr

proc defaultQueryConfig*(): QueryConfig =
  QueryConfig(enabled: false, address: unspecified(25565'u16))
