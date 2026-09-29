## Runtime-run test for shield.nim/arrow.nim (no entity.nim dependency, so
## genuinely runtime-provable, unlike swords.nim/mace.nim which import
## entity.nim's Player and hit the closures-through-vtables crash family
## the moment that module is linked in - not tested here for that reason).
import std/[syncio, assertions]
import shield, arrow

let shieldIds = shieldItemIds()
assert shieldIds.len == 1, "shield should resolve to exactly one id"

let arrowIds = arrowItemIds()
assert arrowIds.len == 3, "arrow item should resolve to 3 ids"
assert arrowIds[0] != arrowIds[1] and arrowIds[1] != arrowIds[2],
  "arrow/tipped_arrow/spectral_arrow must be distinct ids"

echo "shield id: ", $shieldIds[0]
echo "arrow ids: ", $arrowIds[0], " ", $arrowIds[1], " ", $arrowIds[2]
echo "item batch 2 checks passed"
