## Inventory slot implementations.
## Port of upstream/inventory/src/slot.rs
##
## Rust's `Slot: Send + Sync` trait has default method bodies and two
## implementors here (`NormalSlot`, `ArmorSlot`), stored behind `Arc<dyn
## Slot>`. Same shape as inventory.nim's `Inventory`: no trait objects in
## Nimony, so this is a ref object with a manual vtable for the
## overridable methods (`can_insert`/`set_stack_prev`/`mark_dirty`/
## `get_max_item_count`/`can_take_items`), plus free procs for the ones
## Rust gives shared default bodies to.

import itemstub, inventory

type
  InventoryPlayer* = ref object of RootObj
    ## TODO: stub. Real `InventoryPlayer` (screen_handler.rs) is a trait
    ## for the player-side of screen-handler interaction; only used here
    ## as an opaque parameter to callbacks that don't yet do anything with
    ## it, since Player itself isn't ported.

  Slot* = ref object of RootObj
    inventory*: Inventory
    index*: int
    id*: uint8              ## protocol id, assigned by the screen handler
    canInsertImpl*: proc(stack: ItemStack): bool {.closure.}         ## default: true
    setStackPrevImpl*: proc(stack, previousStack: ItemStack) {.closure.} ## default: setStackNoCallbacks
    markDirtyImpl*: proc() {.closure.}                                ## required
    getMaxItemCountImpl*: proc(): uint8 {.closure.}                   ## default: inventory.getMaxCountPerStack
    canTakeItemsImpl*: proc(player: InventoryPlayer): bool {.closure.} ## default: true
    onTakeItemImpl*: proc(player: InventoryPlayer, stack: ItemStack) {.closure.} ## default: markDirty
    onQuickMoveCraftedImpl*: proc(stack, stackPrev: ItemStack) {.closure.}       ## default: no-op
    onClickImpl*: proc(player: InventoryPlayer) {.closure.}           ## default: no-op

proc setId*(s: Slot, id: int) {.inline.} =
  s.id = uint8(id and 0xFF)

proc canInsert*(s: Slot, stack: ItemStack): bool =
  if s.canInsertImpl != nil: s.canInsertImpl(stack) else: true

proc markDirty*(s: Slot) =
  if s.markDirtyImpl != nil: s.markDirtyImpl()

proc getMaxItemCount*(s: Slot): uint8 =
  if s.getMaxItemCountImpl != nil: s.getMaxItemCountImpl()
  else: getMaxCountPerStack(s.inventory)

proc canTakeItems*(s: Slot, player: InventoryPlayer): bool =
  if s.canTakeItemsImpl != nil: s.canTakeItemsImpl(player) else: true

proc getStack*(s: Slot): ItemStack {.inline.} =
  getStack(s.inventory, s.index)

proc getClonedStack*(s: Slot): ItemStack {.inline.} =
  s.getStack()

proc hasStack*(s: Slot): bool {.inline.} =
  not s.getStack().isEmpty()

proc setStackNoCallbacks*(s: Slot, stack: ItemStack) =
  setStack(s.inventory, s.index, stack)
  s.markDirty()

proc setStack*(s: Slot, stack: ItemStack) =
  s.setStackNoCallbacks(stack)

proc setStackPrev*(s: Slot, stack: ItemStack, previousStack: ItemStack) =
  if s.setStackPrevImpl != nil: s.setStackPrevImpl(stack, previousStack)
  else: s.setStackNoCallbacks(stack)

proc getMaxItemCountForStack*(s: Slot, stack: ItemStack): uint8 =
  min(s.getMaxItemCount(), stack.getMaxStackSize())

proc takeStack*(s: Slot, amount: uint8): ItemStack =
  removeStackSpecific(s.inventory, s.index, amount)

proc allowModification*(s: Slot, player: InventoryPlayer): bool =
  s.canInsert(s.getClonedStack()) and s.canTakeItems(player)

proc onTakeItem*(s: Slot, player: InventoryPlayer, stack: ItemStack) =
  if s.onTakeItemImpl != nil: s.onTakeItemImpl(player, stack)
  else: s.markDirty()

proc tryTakeStackRange*(s: Slot, min0: uint8, max0: uint8, player: InventoryPlayer): (bool, ItemStack) =
  ## Returns `(found, stack)` in place of Rust's `Option<ItemStack>`.
  if not s.canTakeItems(player):
    return (false, emptyStack())
  if not s.allowModification(player) and s.getClonedStack().itemCount > max0:
    return (false, emptyStack())
  let takeMin = min(min0, max0)
  var stack = s.takeStack(takeMin)
  if stack.isEmpty():
    (false, emptyStack())
  else:
    if s.getClonedStack().isEmpty():
      s.setStackPrev(emptyStack(), stack)
    (true, stack)

proc safeTake*(s: Slot, min0: uint8, max0: uint8, player: InventoryPlayer): ItemStack =
  let (found, stack) = s.tryTakeStackRange(min0, max0, player)
  if found:
    s.onTakeItem(player, stack)
    stack
  else:
    emptyStack()

proc insertStackCount*(s: Slot, stackIn: ItemStack, count: uint8): ItemStack =
  ## Returns leftover items that couldn't fit, like upstream.
  var stack = stackIn
  if not stack.isEmpty() and s.canInsert(stack):
    var stackSelf = s.getStack()
    let room = s.getMaxItemCountForStack(stack) - stackSelf.itemCount
    let minCount = min(count, min(stack.itemCount, room))
    if minCount != 0:
      if stackSelf.isEmpty():
        s.setStack(stack.split(minCount))
      elif areItemsAndComponentsEqual(stack, stackSelf):
        stack.decrement(minCount)
        stackSelf.increment(minCount)
        s.setStack(stackSelf)
  if stack.isEmpty(): emptyStack() else: stack

proc insertStack*(s: Slot, stack: ItemStack): ItemStack =
  s.insertStackCount(stack, stack.itemCount)

# --- NormalSlot --------------------------------------------------------

proc newNormalSlot*(inv: Inventory, index: int): Slot =
  result = Slot(inventory: inv, index: index, id: 0)
  let self = result
  result.markDirtyImpl = proc() {.closure.} = markDirty(self.inventory)

# --- ArmorSlot -----------------------------------------------------------
#
# Upstream's `can_insert` restricts each equipment slot to the matching
# armor/equippable item type (helmets in head, etc.), which needs the item
# registry's `Item`/`EquipmentSlot`/data-component lookups from `data`
# (unported). Rather than fake that check, `equipmentKind` records which
# slot this is (for callers/UI) and `canInsertImpl` defaults to accepting
# anything - TODO: wire real per-slot item-type validation once `data`'s
# item/equipment tables exist.

type
  EquipmentKind* = enum
    ekHead, ekChest, ekLegs, ekFeet, ekBody, ekSaddle, ekOther

proc newArmorSlot*(inv: Inventory, index: int, equipmentKind: EquipmentKind): Slot =
  result = Slot(inventory: inv, index: index, id: 0)
  let self = result
  result.markDirtyImpl = proc() {.closure.} = markDirty(self.inventory)
  result.setStackPrevImpl = proc(stack, previousStack: ItemStack) {.closure.} =
    self.setStackNoCallbacks(stack)
  result.getMaxItemCountImpl = proc(): uint8 {.closure.} = 1'u8
  result.canTakeItemsImpl = proc(player: InventoryPlayer): bool {.closure.} = true
  # canInsertImpl intentionally left nil (defaults to true) - see note above.
