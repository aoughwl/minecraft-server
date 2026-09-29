## Port of pumpkingmc/crates/pumpkin-util/src/math/vertical_surface_type.rs
##
## Upstream derives `serde::Deserialize` (snake_case). This crate's
## deserialization story isn't ported yet (see pumpkin-nbt/nbt_ops.rs and
## pumpkin-config for where `serde`-shaped decode logic will eventually
## live) - just the type for now.

type
  VerticalSurfaceType* = enum
    ## Upward-facing surface (top of a block/space): ceiling collisions,
    ## hanging placement.
    vstCeiling
    ## Downward-facing surface (bottom of a block/space): ground collisions,
    ## standing placement.
    vstFloor
