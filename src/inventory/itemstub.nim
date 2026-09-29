## Placeholder `Item`/`ItemStack` types.
## TODO: these belong to `data::item`/`data::item_stack` in
## the Rust source (item registry + stack-with-components model). The
## flat name/id/maxStackSize table now exists at `../generated/item.nim`
## (src/data_codegen/gen_item.nim, 1658 real items), but the full
## `components` map (enchantments, durability, custom data - what a real
## `ItemStack` needs beyond count/id) is still unported - see that
## generator's doc comment for why it's scoped down. This stub therefore
## keeps its own `Item`/`ItemStack` shape (id + count) so the many
## existing consumers (src/inventory/*, src/server/item/*) don't need a
## breaking API change, but now backs `getMaxStackSize`/`getName` with a
## real lookup into the generated table instead of a hardcoded guess.
## Replace this file's types with the real ones once `components` lands,
## and every proc here that takes/returns `ItemStack` will need revisiting
## for whatever richer API the real type exposes beyond count/id.

import ../generated/item as realitem

type
  Item* = object
    id*: uint16

  ItemStack* = object
    item*: Item
    itemCount*: uint8

proc findRealItem(id: uint16): (bool, realitem.Item) =
  ## Linear scan over the generated table; `AllItems` is id-ordered so
  ## this could be direct-indexed, but a scan is robust to any future
  ## generator change in ordering/gaps and 1658 entries is cheap.
  for it in realitem.AllItems:
    if it.id == int(id):
      return (true, it)
  (false, realitem.Item())

proc isEmpty*(s: ItemStack): bool {.inline.} =
  s.itemCount == 0 or s.item.id == 0

proc emptyStack*(): ItemStack {.inline.} =
  ItemStack(item: Item(id: 0), itemCount: 0)

proc getItem*(s: ItemStack): Item {.inline.} =
  s.item

proc getMaxStackSize*(s: ItemStack): uint8 {.inline.} =
  ## Real max-stack-size, looked up from the generated item table.
  ## Falls back to the vanilla default (64) for an unknown id (id 0/air,
  ## or an id this port's table doesn't cover for some reason).
  let (found, it) = findRealItem(s.item.id)
  if found: uint8(it.maxStackSize) else: 64'u8

proc getName*(s: ItemStack): string =
  ## Real item name (e.g. "diamond_pickaxe"), looked up from the
  ## generated item table. Empty string if the id isn't found.
  let (found, it) = findRealItem(s.item.id)
  if found: it.name else: ""

proc areItemsAndComponentsEqual*(a, b: ItemStack): bool {.inline.} =
  ## TODO: real equality also compares item *components* (enchantments,
  ## custom data, etc.), not ported yet - id-only for now.
  a.item.id == b.item.id

proc decrement*(s: var ItemStack, amount: uint8) {.inline.} =
  s.itemCount = (if amount >= s.itemCount: 0'u8 else: s.itemCount - amount)

proc increment*(s: var ItemStack, amount: uint8) {.inline.} =
  s.itemCount += amount

proc setCount*(s: var ItemStack, count: uint8) {.inline.} =
  s.itemCount = count

proc isStackable*(s: ItemStack): bool {.inline.} =
  ## TODO: real stackability also checks max-stack-size > 1 and no
  ## uncombinable components (durability items etc.) - not ported yet.
  s.getMaxStackSize() > 1'u8

proc split*(s: var ItemStack, amount: uint8): ItemStack =
  ## Splits `amount` items off `s` into a new stack, decrementing `s` in
  ## place - port of `ItemStack::split`.
  let taken = min(amount, s.itemCount)
  result = ItemStack(item: s.item, itemCount: taken)
  s.decrement(taken)
