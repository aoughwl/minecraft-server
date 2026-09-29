## Window property definitions: container-specific UI properties
## synchronized between server and client (progress bars, fuel indicators,
## etc. in container screens - furnace fire icon, enchant levels, brew
## time, anvil repair cost, ...).
## Port of upstream/inventory/src/window_property.rs
##
## Rust's generic `WindowProperty<T: WindowPropertyTrait>` + a per-enum
## trait impl becomes, here, one concrete `WindowProperty` object holding
## an already-resolved `(id, value)` pair - callers call the matching
## `toId` proc themselves rather than Nimony needing to model the trait
## bound generically. Simpler, same observable behavior.

type
  Furnace* = enum
    ## No `toId` in the upstream file either (only `EnchantmentTable` and
    ## `Anvil` implement `WindowPropertyTrait` there) - ids presumably
    ## assigned elsewhere or via a derive this port hasn't reached yet.
    fpFireIcon
    fpMaximumFuelBurnTime
    fpProgressArrow
    fpMaximumProgress

  EnchantmentTableKind* = enum
    etkLevelRequirement
    etkEnchantmentSeed
    etkEnchantmentId
    etkEnchantmentLevel

  EnchantmentTable* = object
    case kind*: EnchantmentTableKind
    of etkLevelRequirement: levelReqSlot*: uint8
    of etkEnchantmentSeed: discard
    of etkEnchantmentId: enchantIdSlot*: uint8
    of etkEnchantmentLevel: enchantLevelSlot*: uint8

  Beacon* = enum
    bkPowerLevel
    bkFirstPotionEffect
    bkSecondPotionEffect

  Anvil* = enum
    akRepairCost

  BrewingStand* = enum
    bskBrewTime
    bskFuelTime

  Stonecutter* = enum
    skSelectedRecipe

  Loom* = enum
    lkSelectedPattern

  Lectern* = enum
    lekPageNumber

  WindowProperty* = object
    id*: int16
    value*: int16

proc toId*(p: EnchantmentTable): int16 =
  ## TODO: "No more magic numbers" per upstream's own comment.
  case p.kind
  of etkLevelRequirement: int16(p.levelReqSlot)
  of etkEnchantmentSeed: 3'i16
  of etkEnchantmentId: 4'i16 + int16(p.enchantIdSlot)
  of etkEnchantmentLevel: 7'i16 + int16(p.enchantLevelSlot)

proc toId*(p: Anvil): int16 =
  case p
  of akRepairCost: 0'i16

proc newWindowProperty*(id: int16, value: int16): WindowProperty =
  WindowProperty(id: id, value: value)

proc newEnchantmentTableProperty*(p: EnchantmentTable, value: int16): WindowProperty =
  WindowProperty(id: toId(p), value: value)

proc newAnvilProperty*(p: Anvil, value: int16): WindowProperty =
  WindowProperty(id: toId(p), value: value)

proc intoTuple*(w: WindowProperty): (int16, int16) =
  (w.id, w.value)

type
  PropertyDelegate* = ref object of RootObj
    ## Port of the `PropertyDelegate: Sync + Send` trait. Nimony has no
    ## trait-object dispatch (single-dispatch only, no `dyn Trait`), so
    ## this is a base ref object; concrete delegates (furnace, brewing
    ## stand, ...) subclass it and override via a manual vtable of proc
    ## fields once a concrete implementation needs one. Left abstract
    ## here since no concrete delegate exists yet in this port.
    getPropertyImpl*: proc(index: int32): int32
    setPropertyImpl*: proc(index: int32, value: int32)
    getPropertiesSizeImpl*: proc(): int32

proc getProperty*(d: PropertyDelegate, index: int32): int32 = d.getPropertyImpl(index)
proc setProperty*(d: PropertyDelegate, index: int32, value: int32) = d.setPropertyImpl(index, value)
proc getPropertiesSize*(d: PropertyDelegate): int32 = d.getPropertiesSizeImpl()

type
  ExperienceContainer* = ref object of RootObj
    ## Port of the `ExperienceContainer: Send + Sync` trait - same
    ## manual-vtable approach as `PropertyDelegate` above.
    extractExperienceImpl*: proc(): int32

proc extractExperience*(c: ExperienceContainer): int32 = c.extractExperienceImpl()
