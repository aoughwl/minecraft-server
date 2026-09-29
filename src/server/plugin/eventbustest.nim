## Proves EventBus[T] registration+dispatch works, using a real EventData
## payload (PlayerJoinEventData) as T.
##
## Honesty note (see eventbus.nim's doc comment / NIMONY-COMPILER-BUGS.md
## bug #1): this file imports eventbus.nim, whose EventHandler[T] is a
## `{.closure.}` proc stored in a seq field - the exact type-linkage shape
## bug #1 documents as crashing `nimony c -r`, independent of whether a
## handler is ever registered/called. So this test is expected to pass
## `nimony check` but crash at `nimony c -r`, the same as every other
## closure-vtable-shaped file in this port (src/command/, src/server/
## entity/, src/server/block/, src/server/item/, src/inventory/'s screen
## handlers). It is written and run anyway, honestly, rather than skipped,
## so the exact failure point is confirmed rather than assumed.

import std/assertions
import std/syncio
import eventbus
import ../../plugin_api/eventdata

var callCount = 0
var lastMessage = ""

proc onJoin(event: PlayerJoinEventData) =
  inc callCount
  lastMessage = event.joinMessage

proc onJoinSecond(event: PlayerJoinEventData) =
  lastMessage = lastMessage & "!"

var bus = newEventBus[PlayerJoinEventData]()
assert bus.handlerCount == 0

bus.register(onJoin)
bus.register(onJoinSecond)
assert bus.handlerCount == 2

let sampleEvent = PlayerJoinEventData(
  player: (hi: 1'u64, lo: 2'u64),
  joinMessage: "Steve joined the game",
  cancelled: false,
)

dispatch(bus, sampleEvent)
assert callCount == 1
assert lastMessage == "Steve joined the game!"

# Dispatching again accumulates in registration order.
dispatch(bus, sampleEvent)
assert callCount == 2

bus.clear()
assert bus.handlerCount == 0

echo "eventbus: registration + dispatch + clear all pass"
