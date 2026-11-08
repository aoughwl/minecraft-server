## Port of upstream/config/src/networking/proxy.rs

type
  BungeeCordConfig* = object
    enabled*: bool
    secret*: string

  VelocityConfig* = object
    enabled*: bool
    secret*: string

  VineConfig* = object
    enabled*: bool
    publicKey*: string
    secret*: string

  ProxyConfig* = object
    enabled*: bool
    velocity*: VelocityConfig
    bungeecord*: BungeeCordConfig
    vine*: VineConfig

proc defaultBungeeCordConfig*(): BungeeCordConfig =
  BungeeCordConfig(enabled: false, secret: "")

proc defaultVelocityConfig*(): VelocityConfig =
  VelocityConfig(enabled: false, secret: "")

proc defaultVineConfig*(): VineConfig =
  VineConfig(enabled: false, publicKey: "", secret: "")

proc defaultProxyConfig*(): ProxyConfig =
  ProxyConfig(enabled: false, velocity: defaultVelocityConfig(),
              bungeecord: defaultBungeeCordConfig(), vine: defaultVineConfig())
