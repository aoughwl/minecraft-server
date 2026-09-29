## A temporary inventory for crafting grids (2x2 player grid, 3x3 crafting
## table grid, etc.) - cleared on container close, contents consumed by
## crafting.
## Port of upstream/inventory/src/crafting/crafting_inventory.rs
##
## `RecipeInputInventory: Inventory` (recipes.rs) adds `get_width`/
## `get_height` on top of the base `Inventory` trait; Nimony's vtable-based
## `Inventory` has no room for a trait-hierarchy extension, so `width`/
## `height` are carried alongside the returned `Inventory` in this small
## wrapper instead. `recipes.rs`'s `RecipeFinderScreenHandler`/
## `RecipeMatcher`/`RecipeFinder` marker types and `recipe_provider.rs`
## (needs `pumpkin_protocol::codec::recipe`/`pumpkin_data::recipes`, both
## unported) are skipped - nothing behavioral to port yet.

import itemstub, inventory

type
  CraftingInventory* = object
    inv*: Inventory
    width*: uint8
    height*: uint8

proc getWidth*(c: CraftingInventory): int {.inline.} = int(c.width)
proc getHeight*(c: CraftingInventory): int {.inline.} = int(c.height)

proc newCraftingInventory*(width, height: uint8): CraftingInventory =
  var items = newSeq[ItemStack](int(width) * int(height))
  for i in 0 ..< items.len:
    items[i] = emptyStack()

  let inv = Inventory()
  inv.sizeImpl = proc(): int {.closure.} =
    int(width) * int(height)
  inv.isEmptyImpl = proc(): bool {.closure.} =
    for it in items:
      if not it.isEmpty(): return false
    true
  inv.getStackImpl = proc(slot: int): ItemStack {.closure.} =
    if slot >= 0 and slot < items.len: items[slot] else: emptyStack()
  inv.removeStackImpl = proc(slot: int): ItemStack {.closure.} =
    if slot >= 0 and slot < items.len:
      result = items[slot]
      items[slot] = emptyStack()
    else:
      result = emptyStack()
  inv.removeStackSpecificImpl = proc(slot: int, amount: uint8): ItemStack {.closure.} =
    if slot >= 0 and slot < items.len and not items[slot].isEmpty() and amount > 0:
      items[slot].split(amount)
    else:
      emptyStack()
  inv.setStackImpl = proc(slot: int, stack: ItemStack) {.closure.} =
    if slot >= 0 and slot < items.len:
      items[slot] = stack
  inv.clearImpl = proc() {.closure.} =
    for i in 0 ..< items.len:
      items[i] = emptyStack()

  CraftingInventory(inv: inv, width: width, height: height)
