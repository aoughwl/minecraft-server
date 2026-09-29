## Port of pumpkingmc/crates/pumpkin-config/src/fun.rs

type
  FunConfig* = object
    aprilFools*: bool

proc defaultFunConfig*(): FunConfig =
  FunConfig(aprilFools: true)
