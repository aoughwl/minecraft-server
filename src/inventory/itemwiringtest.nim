## Proves itemstub.nim's real-item-table wiring (getMaxStackSize/getName)
## actually resolves against src/generated/item.nim's real data. Split out
## from block-side wiring specifically to AVOID importing
## ../server/block/blockbehaviour (which imports ../server/entity/entity)
## - anything that imports entity.nim currently can't be runtime-verified
## due to the known closures-through-vtables compiler crash (documented in
## src/server/entity/README.md, confirmed 8x independently as of this
## file). Pure item-table wiring has no such dependency, so this one
## actually runs, not just checks.

import std/assertions
import std/syncio
import itemstub

let diamondPick = ItemStack(item: Item(id: 1052), itemCount: 1)
# id 1052 = diamond_pickaxe, confirmed via grep against src/generated/item.nim.
assert diamondPick.getName() == "diamond_pickaxe"
assert diamondPick.getMaxStackSize() == 1'u8
# Tools don't stack.

let stone = ItemStack(item: Item(id: 1), itemCount: 5)
assert stone.getName() == "stone"
assert stone.getMaxStackSize() == 64'u8

let unknown = ItemStack(item: Item(id: 65535), itemCount: 1)
assert unknown.getName() == ""
assert unknown.getMaxStackSize() == 64'u8
# Falls back to the vanilla default for an id the table doesn't cover.

echo "item wiring: OK (runtime-verified)"
