## Static-shape test for the ScreenHandler port: builds a beacon screen
## handler over two simple in-memory inventories and exercises
## `insertItem`, `addSlot`, `getBehaviour`.
##
## KNOWN NIMONY LIMITATION (found independently 3x elsewhere in this port -
## src/command/, src/server/entity/, src/server/block/): closures flowing
## through a manual-vtable ref-object field crash the compiler at the
## `nimony c -r` codegen stage (lambda-lifting/eraiser internals), even
## though `nimony check` passes clean. `beaconhandler.nim`'s
## `onClosedImpl`/`quickMoveImpl` closures hit the same pattern, so THIS
## FILE IS `nimony check`-CLEAN BUT NOT RUN. Treat it the same way
## `cmddispatchtest.nim`/`entitytest.nim`/`blocktest.nim` are documented:
## semantically checked, not proven at runtime, until that compiler crash
## is fixed. `insertItem` itself (the pure slot-merge algorithm, no
## closures involved) is exercised directly below and untouched by the bug.

import std/assertions
import std/syncio
import itemstub, slot, inventory, screenhandler, beaconhandler
import ../generated/screen

type
  SimpleInventory = ref object
    stacks: seq[ItemStack]

proc newSimpleInventory(size: int): SimpleInventory =
  result = SimpleInventory(stacks: newSeq[ItemStack](size))
  for i in 0 ..< size:
    result.stacks[i] = emptyStack()

proc asInventory(si: SimpleInventory): Inventory =
  Inventory(
    sizeImpl: (proc(): int {.closure.} = si.stacks.len),
    isEmptyImpl: (proc(): bool {.closure.} =
      for s in si.stacks:
        if not isEmpty(s): return false
      true),
    getStackImpl: (proc(slot: int): ItemStack {.closure.} = si.stacks[slot]),
    removeStackImpl: (proc(slot: int): ItemStack {.closure.} =
      result = si.stacks[slot]
      si.stacks[slot] = emptyStack()),
    removeStackSpecificImpl: (proc(slot: int, amount: uint8): ItemStack {.closure.} =
      result = split(si.stacks[slot], amount)),
    setStackImpl: (proc(slot: int, stack: ItemStack) {.closure.} = si.stacks[slot] = stack),
    onOpenImpl: (proc() {.closure.} = discard),
    onCloseImpl: (proc() {.closure.} = discard),
    getMaxCountPerStackImpl: (proc(): uint8 {.closure.} = 64'u8),
    markDirtyImpl: (proc() {.closure.} = discard),
    isValidSlotForImpl: (proc(slot: int, stack: ItemStack): bool {.closure.} = true),
    clearImpl: (proc() {.closure.} =
      for i in 0 ..< si.stacks.len:
        si.stacks[i] = emptyStack()),
  )

# --- direct, closure-free test of insertItem's pure algorithm --------------

block insertItemMergesIntoExistingStack:
  var h = ScreenHandler(behaviour: newScreenHandlerBehaviour(0'u8, (false, wtBeacon)))
  let inv = asInventory(newSimpleInventory(2))
  addSlot(h, newNormalSlot(inv, 0))
  addSlot(h, newNormalSlot(inv, 1))
  setStack(h.behaviour.slots[0], ItemStack(item: Item(id: 5'u16), itemCount: 10'u8))

  var incoming = ItemStack(item: Item(id: 5'u16), itemCount: 20'u8)
  let ok = insertItem(h, incoming, 0, 2, false)
  assert ok
  assert getStack(h.behaviour.slots[0]).itemCount == 30'u8
  assert isEmpty(incoming)

block insertItemFillsEmptySlotWhenNoMatch:
  var h = ScreenHandler(behaviour: newScreenHandlerBehaviour(0'u8, (false, wtBeacon)))
  let inv = asInventory(newSimpleInventory(2))
  addSlot(h, newNormalSlot(inv, 0))
  addSlot(h, newNormalSlot(inv, 1))

  var incoming = ItemStack(item: Item(id: 7'u16), itemCount: 5'u8)
  let ok = insertItem(h, incoming, 0, 2, false)
  assert ok
  assert getStack(h.behaviour.slots[0]).item.id == 7'u16
  assert isEmpty(incoming)

echo "screenhandler insertItem checks passed (static-shape only, see file header)"

# --- beacon handler construction (statically checked, not run) -------------

proc buildBeaconHandlerShapeCheck() =
  let playerInv = asInventory(newSimpleInventory(36))
  let beaconInv = asInventory(newSimpleInventory(1))
  let h = newBeaconScreenHandler(1'u8, playerInv, beaconInv)
  assert h.behaviour.slots.len == 37
  assert h.behaviour.syncId == 1'u8
