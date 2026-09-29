## Placeholder `Item`/`ItemStack` types.
## TODO: these belong to `data::item`/`data::item_stack` in
## the Rust source (item registry + stack-with-components model), and
## `data` (1.5M LOC, almost entirely generated block/item/registry
## tables) hasn't been ported yet - see the README's porting-order notes.
## This stub carries just enough shape (an item id and a count) for the
## rest of inventory's slot/container logic, which is mostly
## slot-index and count arithmetic, to be ported and type-check now.
## Replace this file's types with the real ones once data lands,
## and every proc here that takes/returns `ItemStack` will need revisiting
## for whatever richer API the real type exposes (components, NBT-backed
## data, etc.) beyond count/id.

type
  Item* = object
    id*: uint16

  ItemStack* = object
    item*: Item
    itemCount*: uint8

proc isEmpty*(s: ItemStack): bool {.inline.} =
  s.itemCount == 0 or s.item.id == 0

proc emptyStack*(): ItemStack {.inline.} =
  ItemStack(item: Item(id: 0), itemCount: 0)

proc getItem*(s: ItemStack): Item {.inline.} =
  s.item
