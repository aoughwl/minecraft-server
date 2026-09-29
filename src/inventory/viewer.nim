## Tracks how many players currently have a container open.
## Port of upstream/inventory/src/viewer.rs
##
## Nimony's `std/atomics` operates directly on a plain `var T` location
## (GCC/Clang `__atomic_*` builtins - "atomics are operations, not type
## properties"), unlike Rust's `AtomicU16` wrapper type. Same effect,
## different shape: the fields are plain `uint16`, and every access goes
## through `atomicLoad`/`atomicStore`/`atomicFetchAdd`/`atomicFetchSub`.

import std/atomics

type
  ViewerCountTracker* = object
    old*: uint16
    current*: uint16

proc newViewerCountTracker*(): ViewerCountTracker =
  ViewerCountTracker(old: 0'u16, current: 0'u16)

proc openContainer*(t: var ViewerCountTracker) =
  discard atomicFetchAdd(t.current, 1'u16, moRelaxed)

proc closeContainer*(t: var ViewerCountTracker) =
  discard atomicFetchSub(t.current, 1'u16, moRelaxed)

proc getViewerCount*(t: var ViewerCountTracker): uint16 =
  atomicLoad(t.current, moRelaxed)
