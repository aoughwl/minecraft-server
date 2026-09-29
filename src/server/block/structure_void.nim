## Port of upstream/pumpkin/src/block/blocks/structure_void.rs.
## `impl BlockBehaviour for StructureVoidBlock {}` - an entirely empty
## impl, meaning every method falls through to the trait default. In
## Nimony that's just `newBlockBehaviour()` (already all-defaults)
## registered under this block's name in place of `#[pumpkin_block(...)]`.

import blockbehaviour

proc registerStructureVoid*() =
  registerBlock("minecraft:structure_void", newBlockBehaviour())
