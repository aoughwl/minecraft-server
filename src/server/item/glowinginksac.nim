## Port of upstream/pumpkin/src/item/items/glowing_ink_sac.rs's
## `GlowingInkSacItem`. Same shape as ink_sac.nim: empty `ItemBehaviour`,
## the real logic (`apply_to_sign`) is an inherent method needing World/a
## real `BlockEntity`, not ported here.
import std/assertions
import ../../generated/item

proc glowingInkSacItemIds*(): seq[uint16] =
  ## Port of `GlowingInkSacItem::ids`.
  let (found, item) = itemByName("glow_ink_sac")
  assert found, "glow_ink_sac missing from the generated item table"
  @[uint16(item.id)]
