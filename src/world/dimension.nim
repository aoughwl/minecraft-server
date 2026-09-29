## Dimension-to-Level entry point.
## Port of upstream/world/src/dimension.rs
##
## TODO: not ported. `into_level` is a two-line wrapper around
## `Level::from_root_folder`, but `Level` itself (`level.rs`, 1080 lines:
## the region-file-backed world/chunk-storage driver) and
## `data::dimension::Dimension` (the Overworld/Nether/End registry
## entry, defined in the unported 1.5M-line data crate) aren't
## ported. Nothing meaningful to write here yet - this file exists so the
## crate's module shape is documented and the gap is visible in one place
## rather than silently missing.
