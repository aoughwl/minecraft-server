## Scheduler task identity.
## Port of the `SchedulerTaskId` piece of
## upstream/scheduler/src/task.rs (split into its own
## module so `error.nim` can reference it without importing all of
## `task.nim`'s future-based machinery, which isn't ported - see task.nim).

type
  SchedulerTaskId* = object
    value: uint64

proc newSchedulerTaskId*(value: uint64): SchedulerTaskId {.inline.} =
  SchedulerTaskId(value: value)

proc get*(id: SchedulerTaskId): uint64 {.inline.} =
  id.value
