## Equipment storage for an entity (armor slots + off-hand), separate from
## the main inventory.
## Port of upstream/inventory/src/entity_equipment.rs
##
## Upstream keys by `pumpkin_data::data_component_impl::EquipmentSlot`
## (unported - part of `data`'s item/component registry). Keyed here by
## `slot.nim`'s placeholder `EquipmentKind` enum instead, plus an `ekOther`
## catch-all bucket for slot kinds that enum doesn't distinguish (upstream's
## real `EquipmentSlot` carries a body-part index per kind, e.g. multiple
## hotbar-like off-hand-style slots - `ekOther` collapses those to one
## bucket for now). Fixed-size array keyed by `ord(EquipmentKind)` rather
## than a hash map, since the key space is small and known.

import itemstub, slot

type
  EntityEquipment* = object
    equipment: array[EquipmentKind, ItemStack]

proc newEntityEquipment*(): EntityEquipment {.noinit.} =
  for k in low(EquipmentKind) .. high(EquipmentKind):
    result.equipment[k] = emptyStack()

proc put*(e: var EntityEquipment, slot: EquipmentKind, stack: ItemStack): ItemStack =
  ## Returns the previously equipped item, or an empty stack.
  result = e.equipment[slot]
  e.equipment[slot] = stack

proc get*(e: EntityEquipment, slot: EquipmentKind): ItemStack {.inline.} =
  e.equipment[slot]

proc isEmpty*(e: EntityEquipment): bool =
  for k in low(EquipmentKind) .. high(EquipmentKind):
    if not e.equipment[k].isEmpty():
      return false
  true

proc clear*(e: var EntityEquipment) =
  for k in low(EquipmentKind) .. high(EquipmentKind):
    e.equipment[k] = emptyStack()
