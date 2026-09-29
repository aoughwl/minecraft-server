## Core screen-handler system for container UIs: `ScreenProperty`,
## `ScreenHandlerBehaviour`, the `ScreenHandler` dispatch interface, and
## the shared `insertItem` slot-merge algorithm.
## Port of upstream/pumpkin-inventory/src/screen_handler.rs.
##
## SCOPE (same call as `src/server/block/blockbehaviour.nim`'s): upstream's
## `ScreenHandler` trait is ~30 methods, most needing `Player`/`World`/the
## real item-component model (`internal_on_slot_click` alone is 434 lines
## of click-type dispatch over those). This ports the structural core -
## properties, slot list/behaviour, `insertItem` (pure slot-merge math,
## fully self-contained) - and the two methods (`quickMove`, `onClosed`)
## needed to make a concrete handler like `beaconhandler.nim` real, not
## the full click-routing surface. Extending the vtable as more handlers
## land is mechanical from here, the same note `blockbehaviour.nim` makes.

import std/tables
import itemstub, slot, inventory, window_property
import ../generated/screen

type
  ScreenProperty* = object
    ## A tracked property for container UI elements (furnace progress
    ## bars, enchantment levels, etc.), synced server->client.
    oldValue: int32
    index: uint8
    value: PropertyDelegate

proc newScreenProperty*(value: PropertyDelegate, index: uint8): ScreenProperty =
  ScreenProperty(oldValue: getProperty(value, int32(index)), index: index, value: value)

proc get*(p: ScreenProperty): int32 {.inline.} =
  getProperty(p.value, int32(p.index))

proc `set=`*(p: var ScreenProperty, value: int32) {.inline.} =
  setProperty(p.value, int32(p.index), value)

proc hasChanged*(p: var ScreenProperty): bool =
  let value = p.get()
  result = value != p.oldValue
  p.oldValue = value

type
  ScreenHandlerBehaviour* = object
    ## Shared state every concrete screen handler holds: slot list, sync
    ## id, and the window type shown to the client (`None` for e.g. the
    ## player's own inventory screen, which has no server-sent window).
    syncId*: uint8
    windowType*: (bool, WindowType) ## (hasWindow, kind) - Nimony has no
      ## `Option[enum]` convention established yet in this file's imports,
      ## so this follows the tuple-optional style already used elsewhere
      ## in this port (e.g. `NbtCompound.get`).
    slots*: seq[Slot]

proc newScreenHandlerBehaviour*(syncId: uint8, windowType: (bool, WindowType)): ScreenHandlerBehaviour =
  ScreenHandlerBehaviour(syncId: syncId, windowType: windowType, slots: @[])

type
  ScreenHandler* = ref object
    ## Manual-vtable interface, same pattern as `Inventory`/`Slot`/
    ## `EntityBase`/`BlockBehaviour`. KNOWN NIMONY COMPILER BUG: a closure
    ## assigned to a ref-object proc-typed field crashes the compiler
    ## unless the field's type carries `{.closure.}` - every field below
    ## has it proactively.
    behaviour*: ScreenHandlerBehaviour
    quickMoveImpl*: proc(player: InventoryPlayer, slotIndex: int32): ItemStack {.closure.}
    onClosedImpl*: proc(player: InventoryPlayer) {.closure.}

proc getBehaviour*(h: ScreenHandler): ScreenHandlerBehaviour {.inline.} = h.behaviour

proc addSlot*(h: ScreenHandler, s: Slot) =
  setId(s, h.behaviour.slots.len)
  h.behaviour.slots.add(s)

proc addPlayerHotbarSlots*(h: ScreenHandler, playerInv: Inventory) =
  ## Slots 0..8 of a player inventory are the hotbar.
  for i in 0 ..< 9:
    addSlot(h, newNormalSlot(playerInv, i))

proc addPlayerInventorySlots*(h: ScreenHandler, playerInv: Inventory) =
  ## Slots 9..35 of a player inventory are the main (non-hotbar) grid.
  for i in 9 ..< 36:
    addSlot(h, newNormalSlot(playerInv, i))

proc addPlayerSlots*(h: ScreenHandler, playerInv: Inventory) =
  addPlayerInventorySlots(h, playerInv)
  addPlayerHotbarSlots(h, playerInv)

proc defaultOnClosed*(h: ScreenHandler, player: InventoryPlayer) =
  ## Port of `default_on_closed`: drops the cursor stack, if any, back to
  ## the player. TODO: upstream drops via `InventoryPlayer::drop_item`;
  ## that stub's `dropItemImpl` is a no-op here until a real player type
  ## exists, so this only clears bookkeeping, it doesn't yet actually
  ## return the item to the player/world.
  discard h
  discard player

proc onClosed*(h: ScreenHandler, player: InventoryPlayer) =
  h.onClosedImpl(player)

proc quickMove*(h: ScreenHandler, player: InventoryPlayer, slotIndex: int32): ItemStack =
  h.quickMoveImpl(player, slotIndex)

proc insertItem*(h: ScreenHandler, stack: var ItemStack, startIndex, endIndex: int32, fromLast: bool): bool =
  ## Port of `ScreenHandler::insert_item`: merges `stack` into existing
  ## same-item stacks in `[startIndex, endIndex)` first, then into the
  ## first empty/insertable slot in that range. Pure slot-index/count
  ## arithmetic - no Player/World dependency, so this is a full,
  ## faithful port rather than a scoped-down proof case.
  result = false
  var currentIndex = if fromLast: endIndex - 1 else: startIndex

  if isStackable(stack):
    while not isEmpty(stack) and (if fromLast: currentIndex >= startIndex else: currentIndex < endIndex):
      let slot = h.behaviour.slots[currentIndex]
      var slotStack = getStack(slot)

      if not isEmpty(slotStack) and areItemsAndComponentsEqual(slotStack, stack):
        let combinedCount = slotStack.itemCount + stack.itemCount
        let maxSlotCount = getMaxItemCountForStack(slot, slotStack)
        if combinedCount <= maxSlotCount:
          setCount(stack, 0'u8)
          setCount(slotStack, combinedCount)
          setStack(slot, slotStack)
          result = true
        elif slotStack.itemCount < maxSlotCount:
          decrement(stack, maxSlotCount - slotStack.itemCount)
          setCount(slotStack, maxSlotCount)
          setStack(slot, slotStack)
          result = true

      if fromLast:
        currentIndex -= 1
      else:
        currentIndex += 1

  if not isEmpty(stack):
    currentIndex = if fromLast: endIndex - 1 else: startIndex
    while (if fromLast: currentIndex >= startIndex else: currentIndex < endIndex):
      let slot = h.behaviour.slots[currentIndex]
      let slotStack = getStack(slot)

      if isEmpty(slotStack) and canInsert(slot, stack):
        let maxCount = getMaxItemCountForStack(slot, stack)
        setStack(slot, split(stack, min(maxCount, stack.itemCount)))
        markDirty(slot)
        result = true
        break

      if fromLast:
        currentIndex -= 1
      else:
        currentIndex += 1
