## Port of upstream/pumpkin/src/item/items/swords.rs's `SwordItem`.
##
## Same shape as dye.nim's `dyeCanMine`: the only override is `can_mine`,
## which needs just `Player.gamemode` - no `ItemBehaviour` vtable import
## needed (and deliberately avoided, per dye.nim's note, since importing
## itembehaviour.nim's closure-vtable definitions makes even a trivial
## free function un-runnable under the closures-through-vtables crash
## cataloged in NIMONY-COMPILER-BUGS.md #1).
##
## Upstream's id set is `tag::Item::MINECRAFT_SWORDS` (a tag, unported -
## no tag-membership table exists in this port yet). Not resolved here;
## whatever registers `SwordItem` against concrete item ids needs that
## tag data first.
import ../entity/entity
import ../../util/gamemode

proc swordCanMine*(player: Player): bool =
  ## Port of `SwordItem::can_mine`: swords can't "mine" (their use-on-block
  ## action) while in Creative mode.
  player.gamemode != Creative
