## Port of pumpkingmc/crates/pumpkin-config/src/advancement.rs

type
  AdvancementConfig* = object
    saveAdvancements*: bool

proc defaultAdvancementConfig*(): AdvancementConfig =
  AdvancementConfig(saveAdvancements: true)
