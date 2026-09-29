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

proc getMaxStackSize*(s: ItemStack): uint8 {.inline.} =
  ## TODO: real max-stack-size comes from the item's registry data
  ## component; stubbed at the vanilla default (64) until `data` lands.
  64'u8

proc areItemsAndComponentsEqual*(a, b: ItemStack): bool {.inline.} =
  ## TODO: real equality also compares item *components* (enchantments,
  ## custom data, etc.), not ported yet - id-only for now.
  a.item.id == b.item.id

proc decrement*(s: var ItemStack, amount: uint8) {.inline.} =
  s.itemCount = (if amount >= s.itemCount: 0'u8 else: s.itemCount - amount)

proc increment*(s: var ItemStack, amount: uint8) {.inline.} =
  s.itemCount += amount

proc split*(s: var ItemStack, amount: uint8): ItemStack =
  ## Splits `amount` items off `s` into a new stack, decrementing `s` in
  ## place - port of `ItemStack::split`.
  let taken = min(amount, s.itemCount)
  result = ItemStack(item: s.item, itemCount: taken)
  s.decrement(taken)
