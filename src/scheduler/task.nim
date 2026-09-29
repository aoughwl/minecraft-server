## Task identity and causal context.
## Port of pumpkingmc/crates/pumpkin-scheduler/src/task.rs
##
## Ported: `SchedulerTaskId` (in taskid.nim), `TaskContext`. NOT ported:
## `TaskFuture`/`TaskWork`/`TaskRequest`/`TaskHandle` and `TaskHandle`'s
## `impl Future for TaskHandle` - these are `Pin<Box<dyn Future<...>>>` /
## `oneshot::Receiver` tokio-executor plumbing with no Nimony analogue.
## Nimony's async model is `passive` procs + continuations, not
## poll-based futures; porting this layer needs a real design pass once
## the rest of the server settles on how it drives scheduler work, not a
## line-by-line translation. TODO: design the Nimony equivalent (likely a
## `passive proc` + explicit continuation/callback stored per task) once
## `pumpkin` (the crate that actually drives this scheduler) is reached.

import domain, taskid

export taskid.SchedulerTaskId, taskid.newSchedulerTaskId, taskid.get

type
  TaskContext* = object
    ## Owned causal metadata preserved across suspension and worker moves.
    ## A child inherits this chain only while its parent is still valid.
    ## Rust's `owner: Arc<()>` is a liveness token with no payload, used
    ## purely for its Arc refcount/Weak-upgrade semantics to detect a dead
    ## parent; that pattern doesn't translate directly and isn't needed
    ## for the pure data shape, so it's dropped here pending the same
    ## future-plumbing redesign noted above.
    idVal: SchedulerTaskId
    chainVal: SchedulerTaskId
    parentVal: (bool, SchedulerTaskId) ## (hasParent, parent)

proc newTaskContext*(id, chain: SchedulerTaskId, parent: (bool, SchedulerTaskId)): TaskContext {.inline.} =
  TaskContext(idVal: id, chainVal: chain, parentVal: parent)

proc id*(ctx: TaskContext): SchedulerTaskId {.inline.} = ctx.idVal
proc chain*(ctx: TaskContext): SchedulerTaskId {.inline.} = ctx.chainVal
proc parent*(ctx: TaskContext): (bool, SchedulerTaskId) {.inline.} = ctx.parentVal
proc domain*(ctx: TaskContext): ExecutionDomain {.inline.} = globalDomain()
