## The abstract command-issuer type: whoever ran a command (player, console,
## command block, ...).
## Port of upstream/command/src/source.rs
##
## Design decision (the one flagged in `lib.nim` as needed before anything
## above the tokenizer could port): upstream's `CommandSource` is a trait
## generic over the dispatcher (`ArgumentType<S: CommandSource>` etc, so a
## whole tree is parameterized by which source type runs it). Nimony has no
## traits/`dyn`, and no constrained-generic story that would make a
## tree-of-generics like that pleasant. Since real `Player`/console types
## don't exist anywhere in this port yet anyway, this collapses the generic
## into ONE concrete `CommandSource` ref-object type using the manual-vtable
## pattern already established for `Inventory`/`Slot`
## (src/inventory/inventory.nim, slot.nim): a handful of closure fields
## (each needs `{.closure.}` - a bare compiler crash otherwise, see those
## files' comments) plus plain data fields for the parts every source has
## (position/rotation via util's Vector3/Vector2). `Arc<S>`'s trait
## delegation and the blanket `CommandSource for ()`/`for Arc<S>` impls
## don't apply to a single concrete type and are dropped. `TextComponent`
## (util/text, unported) becomes plain `string` for messages, matching the
## simplification already used in cmderrors.nim.
##
## `ReturnValueCallable`/`ResultValueTaker`/`ReturnValue` are ported as
## plain data + a seq of closures, no `Arc` needed since Nimony's ref
## counting already gives shared ownership.

import ../util/vector2, ../util/vector3
import ../server/entity/entity

type
  ReturnValueKind* = enum
    rvkSuccess
    rvkFailure

  ReturnValue* = object
    case kind*: ReturnValueKind
    of rvkSuccess: successValue*: int32
    of rvkFailure: discard

  ReturnValueCallback* = proc(value: ReturnValue) {.closure.}

  EntityAnchor* = enum
    eaFeet
    eaEyes

  CommandSource* = ref object
    ## Manual vtable. `nil` fields fall back to the same defaults upstream's
    ## default trait methods provide.
    sendMessageProc*: proc(message: string) {.closure.}
    sendErrorProc*: proc(error: string) {.closure.}
    hasPermissionProc*: proc(permission: string): bool {.closure.}
    checkBlockLoadedProc*: proc(x, y, z: int32): bool {.closure.}
    position*: Vector3[float64]
    rotation*: Vector2[float32]
    entityAnchor*: EntityAnchor
    resultCallbacks*: seq[ReturnValueCallback]
    player*: nil Player ## `nil` for console/command-block sources; stands
      ## in for upstream's `source.output.as_player()` downcast. Added
      ## for src/server/command/'s concrete command implementations
      ## (e.g. gamemode.nim), which need to reach the issuing player's
      ## entity - not part of the original tokenizer/tree/dispatcher
      ## design pass, but the smallest addition that unblocks them
      ## without inventing a second CommandSource shape.
    displayName*: string ## stands in for `context.source.display_name`
      ## (a `TextComponent` upstream; plain string here, same
      ## simplification the rest of this port uses for the unported
      ## `text` module). Empty for a source with no natural name
      ## (console/command-block).
    broadcastProc*: proc(message: string, senderName: string) {.closure.}
      ## stands in for `context.server().broadcast_message(...)` - there's
      ## no `Server`/player-registry type in this port yet, so `say.nim`/
      ## `me.nim` call through this instead of a real broadcast. `nil`
      ## falls back to echoing to the issuing source only (see
      ## `broadcastMessage` below), which is enough to prove the argument
      ## parsing/dispatch wiring without a fake multi-player fanout.
    stopProc*: proc() {.closure.}
      ## stands in for `crate::stop_server()` - no process-level server
      ## loop exists in this port yet. `nil` is a safe no-op.
    tpsProc*: proc(): float64 {.closure.}
    msptProc*: proc(): float64 {.closure.}
      ## stand in for `context.source.server().get_tps()`/`get_mspt()`
      ## (src/server/command/tps.nim) - no tick-loop/`Server` type exists
      ## in this port yet. `nil` falls back to reporting 0.0.
    reloadProc*: proc() {.closure.}
      ## stands in for `server.reload_datapacks(&server)`
      ## (src/server/command/reload.nim) - same no-`Server`-type gap as
      ## `stopProc`. `nil` is a safe no-op.
    setSaveEnabledProc*: proc(enabled: bool): bool {.closure.}
      ## stands in for iterating `server.worlds` and toggling each
      ## `Level.save_enabled` (src/server/command/saveoff.nim/saveon.nim)
      ## - no world registry exists in this port yet. Returns whether the
      ## call actually changed anything (upstream's `any_disabled`/
      ## `any_enabled`), so `/save-off`/`/save-on` can still report the
      ## already-off/already-on error case correctly. `nil` falls back to
      ## reporting "changed" unconditionally (a single-world assumption,
      ## since there's no registry to say otherwise).
    getSeedProc*: proc(): int64 {.closure.}
      ## stands in for `context.world().level.seed.0`
      ## (src/server/command/seed.nim) - `nil` falls back to `0`.

proc sendMessage*(s: CommandSource, message: string) =
  if s.sendMessageProc != nil:
    s.sendMessageProc(message)

proc sendError*(s: CommandSource, error: string) =
  if s.sendErrorProc != nil:
    s.sendErrorProc(error)
  else:
    sendMessage(s, error)

proc hasPermission*(s: CommandSource, permission: string): bool =
  if s.hasPermissionProc != nil:
    s.hasPermissionProc(permission)
  else:
    true

proc checkBlockLoaded*(s: CommandSource, x, y, z: int32): bool =
  if s.checkBlockLoadedProc != nil:
    s.checkBlockLoadedProc(x, y, z)
  else:
    true

proc broadcastMessage*(s: CommandSource, message: string) =
  if s.broadcastProc != nil:
    s.broadcastProc(message, s.displayName)
  else:
    sendMessage(s, message)

proc stopServer*(s: CommandSource) =
  if s.stopProc != nil:
    s.stopProc()

proc setSaveEnabled*(s: CommandSource, enabled: bool): bool =
  if s.setSaveEnabledProc != nil:
    s.setSaveEnabledProc(enabled)
  else:
    true

proc getSeed*(s: CommandSource): int64 =
  if s.getSeedProc != nil:
    s.getSeedProc()
  else:
    0'i64

proc anchorPosition*(s: CommandSource): Vector3[float64] {.inline.} =
  s.position

proc callResult*(s: CommandSource, value: ReturnValue) =
  for cb in s.resultCallbacks:
    if cb != nil:
      cb(value)

proc newDummySource*(): CommandSource =
  ## Port of `DummySource::dummy()`/`::new()` - a source with no real
  ## backing, used the way upstream uses it: as the default type parameter
  ## for a tree that hasn't been wired to a real player/console yet, and in
  ## tests.
  CommandSource(
    position: Vector3[float64](x: 0.0, y: 0.0, z: 0.0),
    rotation: Vector2[float32](x: 0.0'f32, y: 0.0'f32),
    entityAnchor: eaFeet,
    resultCallbacks: @[],
  )
