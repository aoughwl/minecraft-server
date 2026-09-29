## Port of upstream/pumpkin/src/item/items/knowledge_book.rs's
## `DiscFragmentItem` (a second, unrelated struct sharing the file with
## `KnowledgeBookItem`). Same shape as shield.nim/arrow.nim: no behaviour
## overrides, just an id set.
import std/assertions
import ../../generated/item

proc discFragmentItemId*(): uint16 =
  ## Port of `DiscFragmentItem::ids`: disc_fragment_5.
  let (found, item) = itemByName("disc_fragment_5")
  assert found, "disc_fragment_5 missing from the generated item table"
  uint16(item.id)
