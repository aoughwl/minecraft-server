## Composite inventory combining two inventories into one - used for
## double chests (two single-chest inventories viewed as one 54-slot
## inventory). The first inventory's slots come first; operations are
## delegated to whichever underlying inventory owns the slot index.
## Port of pumpkingmc/crates/pumpkin-inventory/src/double.rs

import itemstub, inventory

proc newDoubleInventory*(first, second: Inventory): Inventory =
  ## Returns a fully-populated `Inventory` (this crate's vtable-based
  ## trait-object stand-in) delegating every operation between `first`
  ## and `second` by slot index, matching upstream's `impl Inventory for
  ## DoubleInventory`.
  result = Inventory()
  result.sizeImpl = proc(): int {.closure.} =
    first.size() + second.size()
  result.isEmptyImpl = proc(): bool {.closure.} =
    first.isEmpty() and second.isEmpty()
  result.getStackImpl = proc(slot: int): ItemStack {.closure.} =
    if slot >= first.size(): second.getStack(slot - first.size())
    else: first.getStack(slot)
  result.removeStackImpl = proc(slot: int): ItemStack {.closure.} =
    if slot >= first.size(): second.removeStack(slot - first.size())
    else: first.removeStack(slot)
  result.removeStackSpecificImpl = proc(slot: int, amount: uint8): ItemStack {.closure.} =
    if slot >= first.size(): second.removeStackSpecific(slot - first.size(), amount)
    else: first.removeStackSpecific(slot, amount)
  result.setStackImpl = proc(slot: int, stack: ItemStack) {.closure.} =
    if slot >= first.size(): second.setStack(slot - first.size(), stack)
    else: first.setStack(slot, stack)
  result.onOpenImpl = proc() {.closure.} =
    first.onOpen()
    second.onOpen()
  result.onCloseImpl = proc() {.closure.} =
    first.onClose()
    second.onClose()
  result.getMaxCountPerStackImpl = proc(): uint8 {.closure.} =
    first.getMaxCountPerStack()
  result.markDirtyImpl = proc() {.closure.} =
    first.markDirty()
    second.markDirty()
  result.isValidSlotForImpl = proc(slot: int, stack: ItemStack): bool {.closure.} =
    if slot >= first.size(): second.isValidSlotFor(slot - first.size(), stack)
    else: first.isValidSlotFor(slot, stack)
  result.clearImpl = proc() {.closure.} =
    # Delegates to both halves the same way the other methods do.
    let firstClear = first.clearImpl
    let secondClear = second.clearImpl
    if firstClear != nil:
      firstClear()
    if secondClear != nil:
      secondClear()
