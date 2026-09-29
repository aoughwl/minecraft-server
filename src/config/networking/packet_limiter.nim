## Port of pumpkingmc/crates/pumpkin-config/src/networking/packet_limiter.rs

type
  PacketLimiterConfig* = object
    enabled*: bool
    maxPacketRate*: float64
    burstCapacity*: float64
    kickMessage*: string

proc defaultPacketLimiterConfig*(): PacketLimiterConfig =
  PacketLimiterConfig(
    enabled: true,
    maxPacketRate: 500.0,
    burstCapacity: 500.0,
    kickMessage: "Kicked for spamming packets",
  )
