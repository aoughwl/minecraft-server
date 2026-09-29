## Port of pumpkingmc/crates/pumpkin-config/src/pvp.rs

type
  PvpConfig* = object
    enabled*: bool
    hurtAnimation*: bool
    protectCreative*: bool
    knockback*: bool
    swing*: bool

proc defaultPvpConfig*(): PvpConfig =
  PvpConfig(enabled: true, hurtAnimation: true, protectCreative: true,
            knockback: true, swing: true)
