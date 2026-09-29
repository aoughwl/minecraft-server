## Module index for the scheduler port.
## Port of upstream/scheduler/src/lib.rs
##
## Ported: domain.nim (ExecutionDomain + *DomainId types), error.nim
## (SchedulerError), taskid.nim (SchedulerTaskId), task.nim (TaskContext),
## scheduler.nim (SchedulerConfig/State/Snapshot).
##
## NOT ported - all future/executor-based plumbing, since it has no
## direct Nimony equivalent (Nimony's async is `passive` procs +
## continuations, not `Pin<Box<dyn Future>>` polling):
## - backend.rs: `ExecutorFuture`, `TaskExecutor` trait.
## - task.rs: `TaskFuture`, `TaskWork`, `TaskRequest`, `TaskHandle` and its
##   `impl Future for TaskHandle`.
## - scheduler.rs: the `SchedulerService` trait (depends on the above).
## - global.rs (326 lines): `GlobalScheduler`, the actual admission/poll
##   driver loop. This is the crate's real logic and is substantial -
##   deliberately deferred rather than force-fit, since it's meaningless
##   without a settled Nimony concurrency design to drive it. TODO: design
##   pass needed once `the upstream server` (the crate that owns the server tick loop)
##   is reached and it's clear what actually drives scheduler turns there.

import domain, error, taskid, task, scheduler

export domain, error, taskid, task, scheduler
