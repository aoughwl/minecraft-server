## Item behaviour interface and registry.
## Port of upstream/pumpkin/src/item/mod.rs (`ItemBehaviour`/`ItemMetadata`
## traits) and upstream/pumpkin/src/item/registry.rs (`ItemRegistry`).
##
## Unlike `block/`, there is no `#[pumpkin_item]` registration macro here -
## upstream registers items with plain `manager.register(SomeItem)` calls in
## `items/mod.rs::default_registry()`, so this ports directly without
## needing the "replace the macro with an explicit table" step
## `blockbehaviour.nim` had to take.
##
## `ItemBehaviour` is a manual-vtable ref object (the established pattern
## for Rust trait objects in this port - see `src/inventory/inventory.nim`,
## `src/server/entity/entity.nim`, `src/server/block/blockbehaviour.nim`).
## Scoped to the methods that only need `Player` (which exists) - `use_on_block`
## needs `Server`/`Block` (unported) and is left out with a TODO, matching
## how `blockbehaviour.nim` scoped itself to what its two proof cases needed.
##
## KNOWN NIMONY RUNTIME BUG (confirmed independently 4x elsewhere in this
## port: src/command/, src/server/entity/, src/server/block/,
## src/inventory/'s screen_handler): closures flowing through a manual
## vtable crash at runtime (`eraiser.nim`/`ParamsTagId` assertion) even when
## `nimony check` passes clean, and one report found the crash triggers just
## from such code being *reachable* in the compiled binary, not from it
## executing. This file is therefore checked, not run - no `nimony c -r`
## proof is claimed for the vtable-dispatch paths.

import ../entity/entity
import ../../inventory/itemstub

type
  Hand* = enum
    ## Port of `pumpkin_util::Hand`.
    handMain
    handOff

  BlockActionResult* = enum
    ## Port of `block::registry::BlockActionResult`. Lives here rather than
    ## in `src/server/block/` because `ItemBehaviour.useOnBlock` returns it
    ## and block/'s own module isn't wired up to export it yet - move this
    ## to block/ and re-export from here once that happens, rather than
    ## defining it twice.
    barSuccess           ## Action was successful (Java: SUCCESS)
    barSuccessServer     ## Successful, server should swing the hand (SUCCESS_SERVER)
    barConsume           ## Blocks other actions from running (CONSUME)
    barFail              ## Allows other actions, but signals failure (FAIL)
    barPass              ## Allows other actions to run (PASS)
    barPassToDefaultBlockAction ## Falls through to the block's normal_use (PASS_TO_DEFAULT_BLOCK_ACTION)

  ItemBehaviour* = ref object
    ## Manual vtable for the `ItemBehaviour` trait. Every field defaults to
    ## upstream's default trait-method body (a proc doing nothing / the
    ## stated default value) via `newDefaultItemBehaviour`; a concrete item
    ## overrides only the fields it needs, matching how a Rust `impl`
    ## overrides only the methods it cares about.
    normalUse*: proc (item: Item, player: Player) {.closure.}
    normalUseWithRotation*: proc (item: Item, player: Player, yaw, pitch: float32) {.closure.}
    normalUseWithHand*: proc (item: Item, player: Player, yaw, pitch: float32, hand: Hand) {.closure.}
    onStoppedUsing*: proc (stack: ItemStack, player: Player) {.closure.}
    onSpearJab*: proc (stack: ItemStack, player: Player) {.closure.}
    onUseTick*: proc (stack: ItemStack, player: Player, remainingUseTicks: int32) {.closure.}
    getUseDuration*: proc (): int32 {.closure.}
    canMine*: proc (player: Player): bool {.closure.}

  ItemRegistry* = ref object
    ## Port of `ItemRegistry`. Upstream keys by `u16` item id via an
    ## `FxHashMap`; a plain `Table[uint16, ItemBehaviour]` is the direct
    ## Nimony equivalent (no need for Rust's `Arc` - Nimony `ref` already
    ## gives shared, GC'd ownership).
    items*: seq[(uint16, nil ItemBehaviour)]

# --- default trait-method bodies -------------------------------------------

proc defaultNormalUse(item: Item, player: Player) {.closure.} =
  discard

proc defaultGetUseDuration(): int32 {.closure.} =
  0'i32

proc defaultCanMine(player: Player): bool {.closure.} =
  true

proc newDefaultItemBehaviour*(): ItemBehaviour =
  ## Builds an `ItemBehaviour` with every field set to upstream's default
  ## trait-method body. A concrete item's constructor calls this then
  ## overrides the fields it needs - e.g.
  ## `result.normalUse = proc (item: Item, player: Player) = ...`.
  result = ItemBehaviour()
  result.normalUse = defaultNormalUse
  result.normalUseWithRotation = proc (item: Item, player: Player, yaw, pitch: float32) {.closure.} =
    result.normalUse(item, player)
  result.normalUseWithHand = proc (item: Item, player: Player, yaw, pitch: float32, hand: Hand) {.closure.} =
    result.normalUseWithRotation(item, player, yaw, pitch)
  result.onStoppedUsing = proc (stack: ItemStack, player: Player) {.closure.} = discard
  result.onSpearJab = proc (stack: ItemStack, player: Player) {.closure.} = discard
  result.onUseTick = proc (stack: ItemStack, player: Player, remainingUseTicks: int32) {.closure.} = discard
  result.getUseDuration = defaultGetUseDuration
  result.canMine = defaultCanMine

# --- ItemRegistry ------------------------------------------------------------

proc newItemRegistry*(): ItemRegistry =
  ItemRegistry(items: @[])

proc indexOf(reg: ItemRegistry, id: uint16): int =
  var i = 0
  while i < reg.items.len:
    if reg.items[i][0] == id:
      return i
    inc i
  result = -1

proc register*(reg: ItemRegistry, ids: openArray[uint16], behaviour: nil ItemBehaviour) =
  ## Port of `ItemRegistry::register`: one behaviour instance can back
  ## several item ids (e.g. a potion item's id set).
  for id in ids:
    let i = indexOf(reg, id)
    if i >= 0:
      reg.items[i] = (id, behaviour)
    else:
      reg.items.add((id, behaviour))

proc getItemBehaviour*(reg: ItemRegistry, id: uint16): nil ItemBehaviour =
  ## Returns `nil` if no behaviour is registered for `id`, matching
  ## upstream's `Option<&Arc<dyn ItemBehaviour>>`.
  let i = indexOf(reg, id)
  if i >= 0: reg.items[i][1] else: nil

proc onUse*(reg: ItemRegistry, stack: ItemStack, player: Player, hand: Hand) =
  ## Port of `ItemRegistry::on_use`. Upstream also handles per-item-group
  ## use cooldowns (`is_on_cooldown`/`start_cooldown`); `Player` doesn't
  ## carry cooldown state yet, so that part is a TODO here, not silently
  ## dropped - see `src/server/entity/entity.nim` for what `Player` covers
  ## so far.
  let b = getItemBehaviour(reg, stack.item.id)
  if b != nil:
    b.normalUseWithHand(stack.item, player, 0.0'f32, 0.0'f32, hand)

proc onStoppedUsing*(reg: ItemRegistry, stack: ItemStack, player: Player) =
  let b = getItemBehaviour(reg, stack.item.id)
  if b != nil:
    b.onStoppedUsing(stack, player)

proc onSpearJab*(reg: ItemRegistry, stack: ItemStack, player: Player) =
  let b = getItemBehaviour(reg, stack.item.id)
  if b != nil:
    b.onSpearJab(stack, player)

proc onUseTick*(reg: ItemRegistry, stack: ItemStack, player: Player, remainingUseTicks: int32) =
  let b = getItemBehaviour(reg, stack.item.id)
  if b != nil:
    b.onUseTick(stack, player, remainingUseTicks)

proc getUseDuration*(reg: ItemRegistry, itemId: uint16): int32 =
  ## Port of `ItemRegistry::get_use_duration`: 0 means "no behaviour-driven
  ## duration", matching upstream's `Option` collapsing `Some(0)` to `None`.
  let b = getItemBehaviour(reg, itemId)
  if b != nil: b.getUseDuration() else: 0'i32

proc canMine*(reg: ItemRegistry, itemId: uint16, player: Player): bool =
  let b = getItemBehaviour(reg, itemId)
  if b != nil: b.canMine(player) else: true

proc shouldTryBlockPlacement*(action: BlockActionResult): bool {.inline.} =
  ## Port of `registry::should_try_block_placement`.
  action == barPass
