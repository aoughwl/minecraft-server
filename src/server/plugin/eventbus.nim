## Minimal event-dispatch core for the plugin manager.
## Port of the dispatch half of upstream/pumpkin/src/plugin/mod.rs's
## `DynEventHandler` mechanism (registration + firing of per-event-kind
## handlers), scoped down from a `Box<dyn ...>` trait-object registry to a
## concrete generic bus.
##
## Design note: upstream's `PluginManager` keeps ONE handler map keyed by
## a type-erased event-kind id, dispatching through `dyn Any` downcasts.
## Nimony has neither trait objects nor a `dyn Any` equivalent, and
## src/plugin_api/eventdata.nim's ~270 event payloads are 270 separate
## concrete object types (there is no single `EventData` sum type - see
## that file's own doc comment for why one wasn't built: a 270-variant
## case object would be enormous and risks the self-recursive/large-
## object-variant C-codegen issues already catalogued). So this is a
## generic `EventBus[T]` instead: one bus per concrete event-payload type,
## instantiated per event kind the caller cares about, rather than one
## bus for everything. A caller wanting to route `PlayerJoinEventData`
## declares `var joinBus: EventBus[PlayerJoinEventData]`, registers
## handlers on it, and calls `dispatch(joinBus, event)` when a join
## happens - the same shape upstream's `on::<PlayerJoinEvent>(handler)`
## has, just without the type-erased common registry underneath it.
##
## Handlers are `{.closure.}` procs stored in a `seq` field - the exact
## "closure in a ref/seq-of-proc field" shape NIMONY-COMPILER-BUGS.md's
## bug #1 documents as crashing at `nimony c -r` (not `nimony check`) once
## such a type is merely linked into the binary, independent of whether a
## handler is ever registered or called. `eventbustest.nim` verifies this
## file's `nimony check` is clean and documents that `nimony c -r` is
## expected to hit that same crash, rather than silently omitting the
## runtime test or claiming a false pass.

type
  EventHandler*[T] = proc(event: T) {.closure.}
    ## A plugin's callback for one event-payload type.

  EventBus*[T] = object
    ## Ordered handler list for one concrete event-payload type `T`.
    handlers*: seq[EventHandler[T]]

proc newEventBus*[T](): EventBus[T] =
  EventBus[T](handlers: @[])

proc register*[T](bus: var EventBus[T], handler: EventHandler[T]) =
  ## Adds a handler. Order is preserve-on-append, matching upstream's
  ## registration-order dispatch (no priority system ported - upstream's
  ## `EventPriority` enum would be a straightforward follow-up: sort
  ## `handlers` by priority at `register` time rather than at `dispatch`
  ## time, to keep the hot path a plain linear walk).
  bus.handlers.add(handler)

proc handlerCount*[T](bus: EventBus[T]): int {.inline.} =
  bus.handlers.len

proc dispatch*[T](bus: EventBus[T], event: T) =
  ## Calls every registered handler with `event`, in registration order.
  ## Uses an indexed `while` rather than `for h in bus.handlers: h(event)`
  ## deliberately - `for x in someSeq: x(...)` over a
  ## `seq[proc(...) {.closure.}]` is NIMONY-COMPILER-BUGS.md bug #1's
  ## documented `nimony check`-time crash trigger; the indexed form is the
  ## established workaround used everywhere else in this port that walks
  ## a seq of closures (e.g. src/command/cmdtree.nim's `meetsRequirements`).
  var i = 0
  while i < bus.handlers.len:
    bus.handlers[i](event)
    inc i

proc clear*[T](bus: var EventBus[T]) =
  bus.handlers = @[]
