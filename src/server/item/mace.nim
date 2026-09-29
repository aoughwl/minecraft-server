## Port of upstream/pumpkin/src/item/items/mace.rs's `MaceItem`.
## Identical shape to swords.nim/dye.nim: only `can_mine` is overridden.
import ../entity/entity
import ../../util/gamemode

proc maceCanMine*(player: Player): bool =
  ## Port of `MaceItem::can_mine`.
  player.gamemode != Creative
