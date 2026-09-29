## Free-standing block-related data types with no World/Player/Entity
## dependency.
## Ported from upstream/pumpkin/src/block/mod.rs (the top of the file only -
## see src/server/block/README.md for why the rest of that module, and all
## of blocks/, entities/, fluid/, registry.rs, viewer.rs, isn't ported yet).

type
  PathComputationType* = enum
    pctLand
    pctWater
    pctAir
