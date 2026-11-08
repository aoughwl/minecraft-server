## Port of upstream/pumpkin/src/block/blocks/fletching_table.rs.
## First user of `normalUse`, a vtable method this file's port added
## (upstream's real `NormalUseArgs<'_>` bundles `&World`/`&Player`/etc.,
## none of which are needed here since this override ignores its args
## entirely and just returns `Pass` - the no-argument scope documented on
## `BlockBehaviour.normalUseImpl` covers this exactly).

import blockbehaviour
import ../item/itembehaviour

proc newFletchingTableBlock*(): BlockBehaviour =
  let b = newBlockBehaviour()
  b.normalUseImpl = (proc(): BlockActionResult {.closure.} =
    barPass)
  b

proc registerFletchingTable*() =
  registerBlock("minecraft:fletching_table", newFletchingTableBlock())
