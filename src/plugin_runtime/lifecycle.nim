## The plain-data slice of pumpkin-plugin-runtime's driver lifecycle state.
## Port of pumpkingmc/crates/pumpkin-plugin-runtime/src/lifecycle.rs's
## `DriverError`/`DriverState` only - see README.md in this directory for
## why the rest of the crate (and the `Lifecycle`/`DriverJoin` types that
## wrap this state in a tokio `watch` channel) isn't ported.

type
  DriverError* = object
    message*: string

  DriverStateKind* = enum
    dskStarting
    dskAccepting
    dskDraining
    dskStopping
    dskStopped
    dskFailed

  DriverState* = object
    case kind*: DriverStateKind
    of dskFailed: error*: DriverError
    else: discard

proc newDriverError*(message: string): DriverError =
  DriverError(message: message)

proc isTerminal*(state: DriverState): bool {.inline.} =
  state.kind in {dskStopped, dskFailed}
