## Port of upstream/util/src/math/vertical_surface_type.rs
##
## Upstream derives `serde::Deserialize` (snake_case). This crate's
## deserialization story isn't ported yet (see nbt/nbt_ops.rs and
## config for where `serde`-shaped decode logic will eventually
## live) - just the type for now.

type
  VerticalSurfaceType* = enum
    ## Upward-facing surface (top of a block/space): ceiling collisions,
    ## hanging placement.
    vstCeiling
    ## Downward-facing surface (bottom of a block/space): ground collisions,
    ## standing placement.
    vstFloor
