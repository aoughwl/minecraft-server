## Screen handler for Lectern blocks: a single book slot, no player slots,
## and the current page synced as container property 0.
## Port of upstream/pumpkin-inventory/src/lectern_screen_handler.rs.
##
## Upstream's `LecternController` trait (page get/set + on-book-taken
## callbacks into the lectern block, which lives outside this crate) has
## no implementor anywhere in this port yet (blocks aren't wired to real
## world state) - same manual-vtable treatment as `PropertyDelegate`.

import itemstub, slot, inventory, screenhandler, window_property
import ../generated/screen

type
  LecternController* = ref object of RootObj
    ## Manual-vtable interface for `LecternController: Send + Sync`.
    currentPageImpl*: proc(): int32 {.closure.}
    setPageImpl*: proc(page: int32) {.closure.}
    onBookTakenImpl*: proc() {.closure.}

proc currentPage*(c: LecternController): int32 {.inline.} = c.currentPageImpl()
proc setPage*(c: LecternController, page: int32) {.inline.} = c.setPageImpl(page)
proc onBookTaken*(c: LecternController) {.inline.} = c.onBookTakenImpl()

const
  PreviousPageButtonId = 1'i32
  NextPageButtonId = 2'i32
  TakeBookButtonId = 3'i32
  JumpToPageOffset = 100'i32 ## Button ids at or above this jump directly
    ## to `id - JumpToPageOffset`.

proc newPageDelegate(controller: LecternController): PropertyDelegate =
  result = PropertyDelegate()
  result.getPropertyImpl = proc(index: int32): int32 {.closure.} =
    if index == 0: currentPage(controller) else: 0
  result.setPropertyImpl = proc(index: int32, value: int32) {.closure.} =
    discard index
    discard value
  result.getPropertiesSizeImpl = proc(): int32 {.closure.} = 1

proc newLecternScreenHandler*(syncId: uint8, inventory: Inventory, controller: LecternController): ScreenHandler =
  result = ScreenHandler(
    behaviour: newScreenHandlerBehaviour(syncId, (true, wtLectern)),
  )

  addSlot(result, newNormalSlot(inventory, 0))
  addProperty(result, newScreenProperty(newPageDelegate(controller), 0))

  let h = result
  let inv = inventory
  let ctrl = controller

  h.quickMoveImpl = proc(player: InventoryPlayer, slotIndex: int32): ItemStack {.closure.} =
    ## The lectern screen has no player slots, so nothing can be
    ## shift-clicked.
    discard player
    discard slotIndex
    emptyStack()

  h.onButtonClickImpl = proc(player: InventoryPlayer, id: int32): bool {.closure.} =
    if id == PreviousPageButtonId:
      setPage(ctrl, currentPage(ctrl) - 1)
      true
    elif id == NextPageButtonId:
      setPage(ctrl, currentPage(ctrl) + 1)
      true
    elif id == TakeBookButtonId:
      let stack = removeStack(inv, 0)
      if isEmpty(stack):
        false
      else:
        markDirty(inv)
        onBookTaken(ctrl)
        offerOrDropStack(player, stack)
        # TODO: upstream calls `send_content_updates()` here to flush
        # property changes to the client; no client-sync layer exists yet
        # in this port.
        true
    elif id >= JumpToPageOffset:
      setPage(ctrl, id - JumpToPageOffset)
      true
    else:
      false
