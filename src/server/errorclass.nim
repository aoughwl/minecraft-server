## Cross-cutting error classification used by the server's top-level error
## handling: does an error warrant kicking the client, at what log
## severity, and what (if any) message the client should see.
## Port of pumpkingmc/crates/pumpkin/src/error.rs
##
## Rust expresses this as a `PumpkinError` trait implemented for each
## concrete error type (`InventoryError`, `ReadingError`,
## `PlayerDataError`), plus a blanket `From<ErrorType> for Box<dyn
## PumpkinError>` so any of them can be handled uniformly. Nimony has no
## trait objects, but it doesn't need one here either: these are three
## unrelated concrete types, not a heterogeneous collection, so plain
## overloaded procs (resolved per-type at compile time, same as Rust's impl
## blocks would resolve at compile time anyway before ever reaching a
## `dyn` object) give the identical call-site ergonomics
## (`isKick(err)`/`severity(err)`/`clientKickReason(err)`) without needing
## a vtable at all. `log()`'s `log_at_level!` macro call is dropped - no
## logging/tracing crate is ported yet; callers can call
## `severity`+`isKick`+`$err` themselves for now.

import ../inventory/invbase
import ../protocol/protobase

type
  ErrorSeverity* = enum
    sevInfo
    sevWarn
    sevError

proc isKick*(e: InventoryError): bool =
  case e.kind
  of iekInvalidSlot, iekClosedContainerInteract, iekInvalidPacket, iekPermissionError:
    true
  of iekLockError, iekOutOfOrderDragging, iekMultiplePlayersDragging:
    false

proc severity*(e: InventoryError): ErrorSeverity =
  case e.kind
  of iekLockError, iekInvalidSlot, iekClosedContainerInteract, iekInvalidPacket,
     iekPermissionError:
    sevError
  of iekOutOfOrderDragging:
    sevInfo
  of iekMultiplePlayersDragging:
    sevWarn

proc clientKickReason*(e: InventoryError): (bool, string) =
  (false, "")

proc isKick*(e: ReadingError): bool {.inline.} = true
proc severity*(e: ReadingError): ErrorSeverity {.inline.} = sevError
proc clientKickReason*(e: ReadingError): (bool, string) =
  (false, "")

# PlayerDataError isn't ported yet (lives in pumpkin-world's data/player_data.rs,
# not yet in src/world/) - its two variants (`Io`/`Nbt`) and their
# `client_kick_reason` message-formatting are straightforward once that
# type exists; add `isKick`/`severity`/`clientKickReason` overloads for it
# here the same way, don't create a separate file for them.
