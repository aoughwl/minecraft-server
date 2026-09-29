## Port of upstream/pumpkin/src/item/items/dye.rs's `DyeItem`.
##
## Only `can_mine` is ported here. `use_on_entity` (dye a sheep/cushion) and
## `apply_to_sign` need: an `ItemBehaviour.useOnEntity` vtable field (doesn't
## exist yet - `itembehaviour.nim` is scoped to `Player`-only methods),
## downcasting from `EntityBase` to concrete `SheepEntity`/`CushionEntity`
## (neither ported), a `Sound` registry (`pumpkin_data::sound`, unported),
## `World.playSound` (the world stub only has block-state read/write), and
## block-entity/sign text types (unported). `can_mine` alone needed none of
## that - just `Player.gamemode`, which the World-stub pass just added.

## Deliberately does NOT import itembehaviour.nim: that module defines the
## ItemBehaviour vtable via closures, and the known "closures-through-
## vtables crash at runtime just from being reachable in the binary" bug
## (5th confirmation - see below) means importing it here would make even
## this trivial function's test un-runnable. `dyeCanMine` is wired into an
## actual ItemBehaviour.canMine field by whatever file builds DyeItem's
## registration, not here.
import ../entity/entity
import ../../util/gamemode

proc dyeCanMine*(player: Player): bool =
  ## Port of `DyeItem::can_mine`: dye can't be used to "mine" (its
  ## use-on-block/use-on-entity actions) while in Creative mode.
  player.gamemode != Creative
