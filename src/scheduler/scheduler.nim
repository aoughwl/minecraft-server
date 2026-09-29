## Scheduler configuration, state, and snapshot counters.
## Port of pumpkingmc/crates/pumpkin-scheduler/src/scheduler.rs
##
## Ported: `SchedulerConfig`, `SchedulerState`, `SchedulerSnapshot`. NOT
## ported: the `SchedulerService` trait (`submit`/`config`/`state`/
## `snapshot` as an object-safe interface returning `TaskHandle`) - it's
## defined in terms of the future-based `task.nim` types that aren't
## ported yet (see task.nim's header comment). TODO: revisit once that
## layer has a Nimony design.
##
## Rust's `NonZeroUsize` (a compile-time-enforced nonzero invariant) has
## no direct Nimony stdlib equivalent found yet; `maximumTasks`/
## `turnsPerPoll` are kept as plain `int` with the nonzero invariant only
## documented, not enforced. Likewise `Duration` becomes a plain
## `float64` of seconds (`slowTurnThresholdSecs`).

type
  SchedulerConfig* = object
    maximumTasksVal: int     ## Must be > 0 (upstream: NonZeroUsize).
    turnsPerPollVal: int     ## Must be > 0 (upstream: NonZeroUsize).
    slowTurnThresholdSecs: float64

proc newSchedulerConfig*(maximumTasks, turnsPerPoll: int, slowTurnThresholdSecs: float64): SchedulerConfig {.inline.} =
  SchedulerConfig(maximumTasksVal: maximumTasks, turnsPerPollVal: turnsPerPoll,
                   slowTurnThresholdSecs: slowTurnThresholdSecs)

proc maximumTasks*(c: SchedulerConfig): int {.inline.} = c.maximumTasksVal
proc turnsPerPoll*(c: SchedulerConfig): int {.inline.} = c.turnsPerPollVal
proc slowTurnThreshold*(c: SchedulerConfig): float64 {.inline.} = c.slowTurnThresholdSecs

type
  SchedulerState* = enum
    ssAccepting
    ssStopped

  SchedulerSnapshot* = object
    ## Counts of admitted tasks. A running task is excluded from `ready`
    ## even if it has already scheduled its next turn by waking itself.
    readyVal: int
    runningVal: int
    pendingVal: int
    slowTurnsVal: uint64

proc newSchedulerSnapshot*(ready, running, pending: int, slowTurns: uint64): SchedulerSnapshot {.inline.} =
  SchedulerSnapshot(readyVal: ready, runningVal: running, pendingVal: pending, slowTurnsVal: slowTurns)

proc ready*(s: SchedulerSnapshot): int {.inline.} = s.readyVal
proc running*(s: SchedulerSnapshot): int {.inline.} = s.runningVal
proc pending*(s: SchedulerSnapshot): int {.inline.} = s.pendingVal
proc slowTurns*(s: SchedulerSnapshot): uint64 {.inline.} = s.slowTurnsVal
