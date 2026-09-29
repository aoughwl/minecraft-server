## `impl BlockBehaviour for TintedGlassBlock {}` - an empty impl, just like
## `structure_void.nim`'s, so it inherits every trait default.
## Port of upstream/pumpkin/src/block/blocks/tinted_glass.rs

import blockbehaviour

proc registerTintedGlass*() =
  registerBlock("minecraft:tinted_glass", newBlockBehaviour())
