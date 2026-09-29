## Generic screen handler for simple grid containers with no special
## behavior: chests (single/double/ender), hoppers, dispensers/droppers,
## barrels, crafters.
## Port of upstream/pumpkin-inventory/src/generic_container_screen_handler.rs.
##
## Upstream's constructor takes `&Arc<PlayerInventory>` (the real
## player-inventory type from the unported `player/` module) plus
## `&dyn InventoryPlayer` (queried only for `is_spectator()`). Neither
## exists yet in this port; following `beaconhandler.nim`'s precedent,
## `playerInventory` is a plain `Inventory`, and `isSpectator` is taken as
## a plain `bool` parameter at the call site rather than queried through
## the still-opaque `InventoryPlayer` stub.
##
## NOTE (faithfully preserved, not a bug in the port): upstream's
## `quick_move` always uses `self.rows * 9` as the container/player-area
## boundary, not `self.rows * self.columns` - correct for every 9-wide
## container (chests, barrels, crafters) but assumes hopper/dispenser-style
## narrower containers (`create_hopper`'s 1x5) still reserve a full 9-wide
## region. Ported as-is; upstream's own `quick_move` doc comment doesn't
## flag this either.

import itemstub, slot, inventory, screenhandler
import ../generated/screen

type
  GenericContainerScreenHandler* = ref object
    inventory*: Inventory
    rows*: uint8
    columns*: uint8
    isSpectator*: bool
    handler*: ScreenHandler

proc addInventorySlots(g: GenericContainerScreenHandler) =
  for i in 0'u8 ..< g.rows:
    for j in 0'u8 ..< g.columns:
      addSlot(g.handler, newNormalSlot(g.inventory, int(j + i * g.columns)))

proc newGenericContainerScreenHandler(screenType: WindowType, syncId: uint8,
    playerInventory: Inventory, inventory: Inventory, rows, columns: uint8,
    isSpectator: bool): GenericContainerScreenHandler =
  result = GenericContainerScreenHandler(
    inventory: inventory, rows: rows, columns: columns, isSpectator: isSpectator,
    handler: ScreenHandler(behaviour: newScreenHandlerBehaviour(syncId, (true, screenType))),
  )

  if not isSpectator:
    onOpen(inventory)

  addInventorySlots(result)
  addPlayerSlots(result.handler, playerInventory)

  let g = result
  g.handler.onClosedImpl = proc(player: InventoryPlayer) {.closure.} =
    defaultOnClosed(g.handler, player)
    # TODO: `player.is_spectator()` - InventoryPlayer is still an opaque
    # stub (see slot.nim), so this can't check the closing player's own
    # spectator state; only the constructor-time `isSpectator` is honored.
    if not g.isSpectator:
      onClose(g.inventory)

  g.handler.quickMoveImpl = proc(player: InventoryPlayer, slotIndex: int32): ItemStack {.closure.} =
    discard player
    var stackLeft = emptyStack()
    let slot = g.handler.behaviour.slots[int(slotIndex)]

    if hasStack(slot):
      var slotStack = getClonedStack(slot)
      stackLeft = slotStack

      let boundary = int32(g.rows) * 9'i32
      if slotIndex < boundary:
        if not insertItem(g.handler, slotStack, boundary, int32(g.handler.behaviour.slots.len), true):
          return emptyStack()
      else:
        if not insertItem(g.handler, slotStack, 0, boundary, false):
          return emptyStack()

      if isEmpty(slotStack):
        setStack(slot, emptyStack())
      else:
        setStack(slot, slotStack)

    stackLeft

proc createGeneric9x3*(syncId: uint8, playerInventory, inventory: Inventory, isSpectator: bool): GenericContainerScreenHandler =
  ## Single chest, ender chest, and similar 9x3 containers.
  newGenericContainerScreenHandler(wtGeneric9x3, syncId, playerInventory, inventory, 3, 9, isSpectator)

proc createGeneric9x6*(syncId: uint8, playerInventory, inventory: Inventory, isSpectator: bool): GenericContainerScreenHandler =
  ## Double chest and similar large containers.
  newGenericContainerScreenHandler(wtGeneric9x6, syncId, playerInventory, inventory, 6, 9, isSpectator)

proc createGeneric3x3*(syncId: uint8, playerInventory, inventory: Inventory, isSpectator: bool): GenericContainerScreenHandler =
  ## Dispensers, droppers, and similar 3x3 containers.
  newGenericContainerScreenHandler(wtGeneric3x3, syncId, playerInventory, inventory, 3, 3, isSpectator)

proc createCrafter3x3*(syncId: uint8, playerInventory, inventory: Inventory, isSpectator: bool): GenericContainerScreenHandler =
  ## Crafter container (9 slots, 3x3 layout).
  newGenericContainerScreenHandler(wtCrafter3x3, syncId, playerInventory, inventory, 3, 3, isSpectator)

proc createHopper*(syncId: uint8, playerInventory, inventory: Inventory, isSpectator: bool): GenericContainerScreenHandler =
  ## Hopper: a single row of 5 slots.
  newGenericContainerScreenHandler(wtHopper, syncId, playerInventory, inventory, 1, 5, isSpectator)
