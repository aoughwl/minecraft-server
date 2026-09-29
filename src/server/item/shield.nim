## Port of upstream/pumpkin/src/item/items/shield.rs's `ShieldItem`.
##
## Upstream overrides nothing (empty `impl ItemBehaviour for ShieldItem`) -
## all behavior is the trait's default. There's therefore no free-standing
## logic to port; the only real content is the item id set the behaviour
## registers against, which this resolves against the real generated item
## table rather than hardcoding a numeric id.
##
## Registration itself (building an `ItemBehaviour` via
## `newDefaultItemBehaviour()` and calling `ItemRegistry.register` with
## these ids) is deliberately not done here: that needs importing
## itembehaviour.nim's closure-vtable definitions, which the established
## convention (see dye.nim) avoids in a file that's meant to stay
## independently testable - whatever builds the real registry wires this
## id list to a default-behaviour instance.
import std/assertions
import ../../generated/item

proc shieldItemIds*(): seq[uint16] =
  ## Port of `ShieldItem::ids`.
  let (found, item) = itemByName("shield")
  assert found, "shield missing from the generated item table"
  @[uint16(item.id)]
