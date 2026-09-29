## NBT support for the upstream server's dynamic serialization operations.
## Port of upstream/nbt/src/nbt_ops.rs
##
## TODO: not started. This entire file is built on `codecs`'s
## `DynamicOps`/`MapLike`/`StructBuilder`/`Number` trait system (a
## Serde-Codec-style dynamic (de)serialization abstraction used pervasively
## elsewhere in the upstream server for config/registry/NBT-agnostic (de)serialization).
## That crate is being ported concurrently elsewhere in this repo
## (src/codecs/, still in progress as of this file). Porting `NbtOps`
## against a moving, not-yet-settled `DynamicOps` Nimony API would mean
## redoing this file once codecs lands - wait for src/codecs/ to have a
## stable `DynamicOps`-equivalent type before starting this.
