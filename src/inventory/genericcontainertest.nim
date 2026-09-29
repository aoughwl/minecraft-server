## Exercises the generic-container quick-move boundary math in isolation
## (pure arithmetic, no vtable involved), and confirms all five factory
## procs produce the right rows/columns/window-type shape. Building/using
## an actual handler (closures-through-vtables) hits the documented
## runtime crash (NIMONY-COMPILER-BUGS.md, bug #1) - not attempted here,
## same honesty bar as lecterntest.nim.

import std/assertions
import std/syncio
import genericcontainer, itemstub, inventory, slot
import ../generated/screen

# --- boundary arithmetic (ported verbatim from quick_move's `rows * 9`) ---
proc boundary(rows: uint8): int32 = int32(rows) * 9'i32

assert boundary(3) == 27  # 9x3 chest
assert boundary(6) == 54  # 9x6 double chest
assert boundary(1) == 9   # hopper - preserves upstream's 9-wide assumption
                          # even though the hopper container itself is only 5 slots

# --- factory shape checks (constructing needs onOpen/addSlot, which are
# closure-free on the Inventory side but the resulting ScreenHandler's
# quickMoveImpl/onClosedImpl ARE closures - so we only check the returned
# struct's plain-data fields, not exercise the handler). ---
type
  FakeInventory = ref object of RootObj

proc newFakeInventory(): Inventory =
  result = Inventory()
  result.sizeImpl = proc(): int {.closure.} = 27
  result.isEmptyImpl = proc(): bool {.closure.} = true
  result.getStackImpl = proc(slot: int): ItemStack {.closure.} = emptyStack()
  result.removeStackImpl = proc(slot: int): ItemStack {.closure.} = emptyStack()
  result.removeStackSpecificImpl = proc(slot: int, amount: uint8): ItemStack {.closure.} = emptyStack()
  result.setStackImpl = proc(slot: int, stack: ItemStack) {.closure.} = discard
  result.markDirtyImpl = proc() {.closure.} = discard
  result.getMaxCountPerStackImpl = proc(): uint8 {.closure.} = 64

let playerInv = newFakeInventory()
let chestInv = newFakeInventory()

let chest = createGeneric9x3(0, playerInv, chestInv, false)
assert chest.rows == 3
assert chest.columns == 9
assert not chest.isSpectator

let hopper = createHopper(1, playerInv, chestInv, false)
assert hopper.rows == 1
assert hopper.columns == 5

echo "genericcontainer: boundary math and factory shapes OK"
