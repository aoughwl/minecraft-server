## Shared error type for the inventory crate.
## Port of upstream/inventory/src/error.rs
##
## Same house convention as src/nbt/nbtbase.nim: Nimony has no
## Nim-compatible exceptions, so this is a plain error-kind enum (no
## Result[T] wrapper defined here yet - individual inventory procs will
## define their own XResult[T] against this InventoryError as needed).

type
  InventoryErrorKind* = enum
    iekLockError               ## Unable to lock an inventory or slot.
    iekInvalidSlot              ## The specified slot index is invalid or out of bounds.
    iekClosedContainerInteract  ## A player tried to interact with a closed container.
    iekMultiplePlayersDragging  ## Multiple players dragged in the same container at once.
    iekOutOfOrderDragging       ## Drag operation performed out of order.
    iekInvalidPacket            ## The received inventory packet is malformed or invalid.
    iekPermissionError          ## The player lacks permission for this operation.

  InventoryError* = object
    kind*: InventoryErrorKind
    ## Set only for `iekClosedContainerInteract`: the interacting player's entity id.
    playerEntityId*: int32

proc lockError*(): InventoryError = InventoryError(kind: iekLockError)
proc invalidSlot*(): InventoryError = InventoryError(kind: iekInvalidSlot)
proc closedContainerInteract*(entityId: int32): InventoryError =
  InventoryError(kind: iekClosedContainerInteract, playerEntityId: entityId)
proc multiplePlayersDragging*(): InventoryError = InventoryError(kind: iekMultiplePlayersDragging)
proc outOfOrderDragging*(): InventoryError = InventoryError(kind: iekOutOfOrderDragging)
proc invalidPacket*(): InventoryError = InventoryError(kind: iekInvalidPacket)
proc permissionError*(): InventoryError = InventoryError(kind: iekPermissionError)

proc `$`*(e: InventoryError): string =
  case e.kind
  of iekLockError: "Unable to lock"
  of iekInvalidSlot: "Invalid slot"
  of iekClosedContainerInteract:
    "Player '" & $e.playerEntityId & "' tried to interact with a closed container"
  of iekMultiplePlayersDragging: "Multiple players dragging in a container at once"
  of iekOutOfOrderDragging: "Out of order dragging"
  of iekInvalidPacket: "Invalid inventory packet"
  of iekPermissionError: "Player does not have enough permissions"
