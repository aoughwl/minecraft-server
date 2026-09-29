## Screen handler for Beacon blocks: a single payment slot plus the
## player's inventory slots.
## Port of upstream/pumpkin-inventory/src/beacon_screen_handler.rs.
##
## Upstream takes `player_inventory: &Arc<PlayerInventory>` (the real
## player-inventory type from the unported `player/` module) separately
## from the generic `inventory: Arc<dyn Inventory>` parameter. Since
## `player/player_inventory.rs` isn't ported, this takes a plain
## `Inventory` for both - the vtable interface is the same shape
## `PlayerInventory` would present here (`addPlayerSlots` only needs
## `Inventory`'s ops), so nothing about the beacon logic itself is faked.

import itemstub, slot, inventory, screenhandler
import ../generated/screen

proc newBeaconScreenHandler*(syncId: uint8, playerInventory: Inventory, beaconInventory: Inventory): ScreenHandler =
  result = ScreenHandler(
    behaviour: newScreenHandlerBehaviour(syncId, (true, wtBeacon)),
  )
  onOpen(beaconInventory)

  addSlot(result, newNormalSlot(beaconInventory, 0))
  addPlayerSlots(result, playerInventory)

  let h = result
  h.onClosedImpl = proc(player: InventoryPlayer) {.closure.} =
    defaultOnClosed(h, player)
    onClose(beaconInventory)

  h.quickMoveImpl = proc(player: InventoryPlayer, slotIndex: int32): ItemStack {.closure.} =
    ## From the beacon payment slot (0): move to player inventory.
    ## From player inventory (1+): move into the beacon payment slot.
    var stackLeft = emptyStack()
    let slot = h.behaviour.slots[int(slotIndex)]

    if hasStack(slot):
      var slotStack = getClonedStack(slot)
      stackLeft = slotStack

      if slotIndex == 0:
        if not insertItem(h, slotStack, 1, int32(h.behaviour.slots.len), true):
          return emptyStack()
      else:
        if not insertItem(h, slotStack, 0, 1, false):
          return emptyStack()

      if isEmpty(slotStack):
        setStack(slot, emptyStack())
      else:
        setStack(slot, slotStack)

    stackLeft
