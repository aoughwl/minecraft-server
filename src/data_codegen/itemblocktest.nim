## Run-verifies src/generated/item.nim and src/generated/block.nim against
## known values from assets/items.json/blocks.json (`nimony c -r`, not just
## `nimony check`).

import std/[syncio, assertions]
import ../generated/item
import ../generated/blockdata

assert AllItems.len == 1658
assert AllBlocks.len == 1286

let (foundStone, stoneItem) = itemById(1)
assert foundStone
assert stoneItem.name == "stone"
assert stoneItem.maxStackSize == 64

let (foundPick, pickItem) = itemByName("diamond_pickaxe")
assert foundPick
assert pickItem.maxStackSize == 1

let (foundAir, airItem) = itemByName("air")
assert foundAir
assert airItem.id == 0

let (foundStoneBlock, stoneBlock) = blockByName("stone")
assert foundStoneBlock
assert stoneBlock.id == 1
assert stoneBlock.hardness == 1.5
assert stoneBlock.blastResistance == 6.0
assert stoneBlock.itemId == 1
assert stoneBlock.defaultStateId == 1

let (foundAirBlock, airBlock) = blockById(0)
assert foundAirBlock
assert airBlock.name == "air"
assert airBlock.translationKey == "block.minecraft.air"

let (missingItem, _) = itemByName("this_item_does_not_exist")
assert not missingItem

echo "item/block table checks passed"
