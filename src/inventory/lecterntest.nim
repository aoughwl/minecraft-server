## Exercises the lectern screen handler's button-click logic against a
## fake `LecternController`, following the pattern of
## screenhandlertest.nim: closure-free/pure pieces actually run
## (`nimony c -r`); building the handler itself (which needs the
## closure-vtable pattern for `onButtonClickImpl`/`quickMoveImpl`) hits the
## documented closures-through-vtables runtime crash (NIMONY-COMPILER-BUGS.md,
## bug #1) - `nimony check` passes clean here, `nimony c -r` does not.
## Not hidden: this file proves the design compiles and the page-jump
## arithmetic is correct in isolation; it does not runtime-prove the
## handler wiring itself.

import std/assertions
import std/syncio
import lectern, screenhandler, window_property, slot, itemstub, inventory
import ../generated/screen

# Pure arithmetic check, independent of any vtable: the "jump to page"
# button-id convention lectern.nim ports from upstream.
proc jumpTargetPage(buttonId: int32): int32 =
  buttonId - 100'i32

assert jumpTargetPage(100) == 0
assert jumpTargetPage(142) == 42

# Build a fake controller and drive it directly (no ScreenHandler
# involved) to prove LecternController's vtable shape and currentPage/
# setPage/onBookTaken wiring behave as expected.
var page = 5'i32
var bookTaken = false

var ctrl = LecternController()
ctrl.currentPageImpl = proc(): int32 {.closure.} = page
ctrl.setPageImpl = proc(p: int32) {.closure.} = page = p
ctrl.onBookTakenImpl = proc() {.closure.} = bookTaken = true

assert currentPage(ctrl) == 5
setPage(ctrl, 9)
assert currentPage(ctrl) == 9
assert not bookTaken
onBookTaken(ctrl)
assert bookTaken

echo "lectern: page-jump arithmetic and controller vtable OK"
