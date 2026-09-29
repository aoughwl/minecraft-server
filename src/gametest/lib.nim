## Module index / scope note for the pumpkin-gametest port.
## Port of pumpkingmc/crates/pumpkin-gametest/src/lib.rs
##
## Ported: error.nim (error.rs), model.nim (model.rs), rotation_stub.nim
## (a hand-copied slice of pumpkin-data's block_rotation.rs that model.nim
## needs - see its own header).
##
## NOT ported, all blocked on the same two things:
##   1. `pumpkin_util::math::position::BlockPos` and `pumpkin_world::
##      world::BlockFlags`/`pumpkin_data::BlockStateId` - none exist in
##      this port yet (util's math/ files and all of pumpkin-world remain).
##   2. Rust's `#[async_trait]` on `GameTestWorld` (world.rs) and the
##      manager/runner state machines (manager.rs 391 LOC, runner/mod.rs
##      442 LOC, runner/state.rs, helper.rs, structure/placement.rs 389
##      LOC, structure/template.rs 223 LOC, block_based/test.rs) - these
##      are trait-object/async-driven and need the same design pass noted
##      in src/scheduler/lib.nim (Nimony has no traits or poll-based
##      futures; it's `passive` procs + continuations instead). Doing this
##      well requires knowing what's driving the server tick loop, which
##      isn't decided yet this early in the port.
## Revisit once pumpkin-world/pumpkin-util's math types land and the
## scheduler/tick-loop design is settled.
