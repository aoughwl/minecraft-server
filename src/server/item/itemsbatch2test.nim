## Runtime-run test for shield.nim/arrow.nim/inksac.nim/glowinginksac.nim/
## discfragment.nim (no entity.nim dependency, so genuinely runtime-provable,
## unlike swords.nim/mace.nim which import entity.nim's Player and hit the
## closures-through-vtables crash family the moment that module is linked
## in - not tested here for that reason).
import std/[syncio, assertions]
import shield, arrow, inksac, glowinginksac, discfragment

let shieldIds = shieldItemIds()
assert shieldIds.len == 1, "shield should resolve to exactly one id"

let arrowIds = arrowItemIds()
assert arrowIds.len == 3, "arrow item should resolve to 3 ids"
assert arrowIds[0] != arrowIds[1] and arrowIds[1] != arrowIds[2],
  "arrow/tipped_arrow/spectral_arrow must be distinct ids"

let inkSacIds = inkSacItemIds()
assert inkSacIds.len == 1, "ink_sac should resolve to exactly one id"

let glowInkSacIds = glowingInkSacItemIds()
assert glowInkSacIds.len == 1, "glow_ink_sac should resolve to exactly one id"
assert glowInkSacIds[0] != inkSacIds[0], "ink_sac and glow_ink_sac must be distinct ids"

let discFragId = discFragmentItemId()
assert discFragId != shieldIds[0], "disc_fragment_5 must differ from shield"

echo "shield id: ", $shieldIds[0]
echo "arrow ids: ", $arrowIds[0], " ", $arrowIds[1], " ", $arrowIds[2]
echo "ink_sac id: ", $inkSacIds[0]
echo "glow_ink_sac id: ", $glowInkSacIds[0]
echo "disc_fragment_5 id: ", $discFragId
echo "item batch 2 checks passed"
