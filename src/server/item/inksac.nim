## Port of upstream/pumpkin/src/item/items/ink_sac.rs's `InkSacItem`.
##
## `impl ItemBehaviour for InkSacItem` overrides nothing (just `as_any`) -
## all behavior is the trait's default, same as shield.rs/arrow.rs. The
## real logic lives in `InkSacItem::apply_to_sign` (an inherent method, not
## an `ItemBehaviour` override), which needs `UseWithItemArgs`'s `world`/
## a real `BlockEntity` and isn't ported here.
import std/assertions
import ../../generated/item

proc inkSacItemIds*(): seq[uint16] =
  ## Port of `InkSacItem::ids`.
  let (found, item) = itemByName("ink_sac")
  assert found, "ink_sac missing from the generated item table"
  @[uint16(item.id)]
