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
