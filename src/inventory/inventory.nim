## Core `Inventory`/`Clearable` interface, and NBT slot-array sync helpers.
## Port of pumpkingmc/crates/pumpkin-inventory/src/inventory/inventory.rs
##
## Rust's `Inventory: Send + Sync + Clearable` is a trait with default
## method bodies, stored behind `Arc<dyn Inventory>` for dynamic dispatch
## (double chests, player inventories, etc. all implement it and get
## stored/passed around uniformly). Nimony has no trait objects (single
## dispatch only, no `dyn Trait`) - this is ported as a ref object holding
## a manual vtable of proc fields for the required (overridable) methods,
## plus free procs for the ones Rust gives default bodies to (mirroring
## `count`/`contains_any`/`write_inventory_nbt`/... exactly, just as
## functions over the vtable instead of trait default methods). A concrete
## inventory (SimpleInventory, PlayerInventory, DoubleInventory, ...)
## constructs an `Inventory` by filling in the vtable fields.

import itemstub
import "../nbt/tag"

type
  Inventory* = ref object of RootObj
    sizeImpl*: proc(): int {.closure.}
    isEmptyImpl*: proc(): bool {.closure.}
    getStackImpl*: proc(slot: int): ItemStack {.closure.}
    removeStackImpl*: proc(slot: int): ItemStack {.closure.}
    removeStackSpecificImpl*: proc(slot: int, amount: uint8): ItemStack {.closure.}
    setStackImpl*: proc(slot: int, stack: ItemStack) {.closure.}
    onOpenImpl*: proc() {.closure.}  ## default: no-op
    onCloseImpl*: proc() {.closure.}  ## default: no-op
    getMaxCountPerStackImpl*: proc(): uint8 {.closure.}  ## default: 99
    markDirtyImpl*: proc() {.closure.}  ## default: no-op
    isValidSlotForImpl*: proc(slot: int, stack: ItemStack): bool {.closure.}  ## default: true
    clearImpl*: proc() {.closure.}  ## Clearable::clear

proc size*(inv: Inventory): int {.inline.} = inv.sizeImpl()
proc isEmpty*(inv: Inventory): bool {.inline.} = inv.isEmptyImpl()
proc getStack*(inv: Inventory, slot: int): ItemStack {.inline.} = inv.getStackImpl(slot)
proc removeStack*(inv: Inventory, slot: int): ItemStack {.inline.} = inv.removeStackImpl(slot)
proc removeStackSpecific*(inv: Inventory, slot: int, amount: uint8): ItemStack {.inline.} =
  inv.removeStackSpecificImpl(slot, amount)
proc setStack*(inv: Inventory, slot: int, stack: ItemStack) {.inline.} =
  inv.setStackImpl(slot, stack)

proc onOpen*(inv: Inventory) =
  if inv.onOpenImpl != nil: inv.onOpenImpl()
proc onClose*(inv: Inventory) =
  if inv.onCloseImpl != nil: inv.onCloseImpl()

proc getMaxCountPerStack*(inv: Inventory): uint8 =
  if inv.getMaxCountPerStackImpl != nil: inv.getMaxCountPerStackImpl() else: 99'u8

proc markDirty*(inv: Inventory) =
  if inv.markDirtyImpl != nil: inv.markDirtyImpl()

proc isValidSlotFor*(inv: Inventory, slot: int, stack: ItemStack): bool =
  if inv.isValidSlotForImpl != nil: inv.isValidSlotForImpl(slot, stack) else: true

proc count*(inv: Inventory, item: Item): uint8 =
  result = 0
  for i in 0 ..< inv.size():
    let stack = inv.getStack(i)
    if stack.getItem().id == item.id:
      result += stack.itemCount

proc containsAnyPredicate*(inv: Inventory, predicate: proc(s: ItemStack): bool): bool =
  for i in 0 ..< inv.size():
    if predicate(inv.getStack(i)):
      return true
  false

proc containsAny*(inv: Inventory, items: seq[Item]): bool =
  ## Ported as a direct loop rather than reusing `containsAnyPredicate`
  ## with a closure - closing over `items` there tripped Nimony's borrow
  ## checker ("path is not borrowable"). Same observable behavior as
  ## upstream's `contains_any_predicate(&|stack| ...)`.
  for i in 0 ..< inv.size():
    let stack = inv.getStack(i)
    if stack.isEmpty():
      continue
    for it in items:
      if it.id == stack.item.id:
        return true
  false

proc canTransferTo*(inv: Inventory, hopperInventory: Inventory, slot: int, stack: ItemStack): bool =
  ## Default body always returns true, same as upstream; parameters are
  ## accepted (and ignored, like Rust's `_`-prefixed ones) so overriders
  ## have the full signature to work with.
  true

# --- NBT compound helpers -----------------------------------------------
# compound.rs's convenience accessors (`put_byte`/`get_byte`/`put_list`/
# `get_list`/`extract_compound`) haven't been ported to src/nbt/ yet
# (only the core child_tags map ops and (de)serialization have), so the
# specific handful this file needs are implemented locally against the
# NbtCompound/NbtTag API that does exist.

proc putByte(c: var NbtCompound, name: string, value: int8) =
  put(c, name, NbtTag(kind: ntkByte, byteVal: value))

proc getByte(c: NbtCompound, name: string): (bool, int8) =
  let (found, tag) = get(c, name)
  if found and tag.kind == ntkByte:
    (true, tag.byteVal)
  else:
    (false, 0'i8)

proc extractCompound(tag: NbtTag): (bool, NbtCompound) =
  if tag.kind == ntkCompound:
    (true, tag.compoundVal)
  else:
    (false, newCompound())

proc putList(c: var NbtCompound, name: string, list: seq[NbtTag]) =
  put(c, name, NbtTag(kind: ntkList, listVal: list))

proc getList(c: NbtCompound, name: string): (bool, seq[NbtTag]) =
  let (found, tag) = get(c, name)
  if found and tag.kind == ntkList:
    (true, tag.listVal)
  else:
    (false, @[])

proc writeItemStack(stack: ItemStack, c: var NbtCompound) =
  ## TODO: stub. The real `ItemStack::write_item_stack` (pumpkin_data)
  ## writes item id + count + full component data; this writes only what
  ## the stub `ItemStack` in itemstub.nim carries.
  putByte(c, "id", cast[int8](stack.item.id and 0xFF'u16))
  putByte(c, "count", cast[int8](stack.itemCount))

proc readItemStack(c: NbtCompound): (bool, ItemStack) =
  ## TODO: stub counterpart to `writeItemStack`.
  let (foundId, idByte) = getByte(c, "id")
  let (foundCount, countByte) = getByte(c, "count")
  if foundId and foundCount:
    (true, ItemStack(item: Item(id: uint16(cast[uint8](idByte))), itemCount: cast[uint8](countByte)))
  else:
    (false, emptyStack())

proc writeInventoryNbt*(inv: Inventory, nbt: var NbtCompound, includeEmpty: bool) =
  var slots: seq[NbtTag] = @[]
  let size = inv.size()
  for i in 0 ..< size:
    let stack = inv.getStack(i)
    if not stack.isEmpty():
      var itemCompound = newCompound()
      putByte(itemCompound, "Slot", cast[int8](uint8(i) and 0xFF'u8))
      writeItemStack(stack, itemCompound)
      slots.add(NbtTag(kind: ntkCompound, compoundVal: itemCompound))
  if includeEmpty or slots.len > 0:
    putList(nbt, "Items", slots)

proc syncReadItemsFromNbt*(nbt: NbtCompound, stacks: var seq[ItemStack]) =
  let (found, list) = getList(nbt, "Items")
  if found:
    for tag in list:
      let (foundCompound, itemCompound) = extractCompound(tag)
      if foundCompound:
        let (foundSlot, slotByte) = getByte(itemCompound, "Slot")
        if foundSlot:
          let slot = int(cast[uint8](slotByte))
          if slot < stacks.len:
            let (foundStack, itemStack) = readItemStack(itemCompound)
            if foundStack:
              stacks[slot] = itemStack

proc readData*(inv: Inventory, nbt: NbtCompound, stacks: var seq[ItemStack]) =
  syncReadItemsFromNbt(nbt, stacks)

proc syncWriteItemsToNbt*(items: seq[ItemStack], nbt: var NbtCompound) =
  var slots: seq[NbtTag] = @[]
  for i, stack in items:
    if not stack.isEmpty():
      var itemNbt = newCompound()
      putByte(itemNbt, "Slot", cast[int8](uint8(i) and 0xFF'u8))
      writeItemStack(stack, itemNbt)
      slots.add(NbtTag(kind: ntkCompound, compoundVal: itemNbt))
  if slots.len > 0:
    putList(nbt, "Items", slots)

type
  ComparableInventory* = object
    ## Port of `ComparableInventory(pub Arc<dyn Inventory>)`: equality and
    ## hashing are by reference identity, not by content - two
    ## `ComparableInventory`s are equal iff they wrap the same `Inventory`
    ## ref.
    inv*: Inventory

proc `==`*(a, b: ComparableInventory): bool {.inline.} =
  cast[pointer](a.inv) == cast[pointer](b.inv)

proc hash*(c: ComparableInventory): int {.inline.} =
  cast[int](cast[pointer](c.inv))
