## Port of upstream/pumpkin/src/item/items/arrow.rs's `ArrowItem`.
## Same shape as shield.nim: no behaviour overrides, just an id set - here
## three real items sharing one behaviour instance (the way `ItemRegistry`
## already supports one behaviour backing several ids).
import std/assertions
import ../../generated/item

proc arrowItemIds*(): seq[uint16] =
  ## Port of `ArrowItem::ids`: arrow, tipped_arrow, spectral_arrow.
  result = @[]
  for name in ["arrow", "tipped_arrow", "spectral_arrow"]:
    let (found, item) = itemByName(name)
    assert found, name & " missing from the generated item table"
    result.add(uint16(item.id))
