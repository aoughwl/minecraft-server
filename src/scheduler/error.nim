## Scheduler error type.
## Port of pumpkingmc/crates/pumpkin-scheduler/src/error.rs
##
## Rust's `SchedulerError` is a plain `Error`-deriving enum used as the `E`
## in `Result<T, SchedulerError>`; it isn't Rust exception machinery. It
## therefore ports directly to a Nimony value type (no `NbtResult`-style
## wrapper needed here - callers build their own `Result[T, SchedulerError]`
## per proc, same as upstream's per-call `Result<T, SchedulerError>`).

import domain
import taskid

type
  SchedulerErrorKind* = enum
    seQueueFull
    seUnsupportedDomain
    seForeignContext
    seInactiveParent
    seTaskIdsExhausted
    seTaskPanicked
    seStopped
    seBackend

  SchedulerError* = object
    case kind*: SchedulerErrorKind
    of seQueueFull: queueFullDomain*: ExecutionDomain
    of seUnsupportedDomain: unsupportedDomain*: ExecutionDomain
    of seForeignContext: discard
    of seInactiveParent: inactiveParentTask*: SchedulerTaskId
    of seTaskIdsExhausted: discard
    of seTaskPanicked:
      panickedTask*: SchedulerTaskId
      panicMessage*: string
    of seStopped: discard
    of seBackend: backendMessage*: string

proc queueFull*(domain: ExecutionDomain): SchedulerError {.inline.} =
  SchedulerError(kind: seQueueFull, queueFullDomain: domain)

proc unsupportedDomain*(domain: ExecutionDomain): SchedulerError {.inline.} =
  SchedulerError(kind: seUnsupportedDomain, unsupportedDomain: domain)

proc foreignContext*(): SchedulerError {.inline.} =
  SchedulerError(kind: seForeignContext)

proc inactiveParent*(task: SchedulerTaskId): SchedulerError {.inline.} =
  SchedulerError(kind: seInactiveParent, inactiveParentTask: task)

proc taskIdsExhausted*(): SchedulerError {.inline.} =
  SchedulerError(kind: seTaskIdsExhausted)

proc taskPanicked*(task: SchedulerTaskId, message: string): SchedulerError {.inline.} =
  SchedulerError(kind: seTaskPanicked, panickedTask: task, panicMessage: message)

proc stoppedError*(): SchedulerError {.inline.} =
  SchedulerError(kind: seStopped)

proc backendError*(message: string): SchedulerError {.inline.} =
  SchedulerError(kind: seBackend, backendMessage: message)
