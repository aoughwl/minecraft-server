# Phase 3 #17: region-sharded simulation

## Shipped (tested, `src/server/sim/regions.aowl`, `simtest.aowl`)

Pure planner, no threads, no world access.

* `planPhases(active, tileSize, margin)`: square tiles of `tileSize` chunks, coloured by tile parity (4 phases). With
  `tileSize > 2 * margin` (`validTileSize`; otherwise it returns no plan) no chunk of one tile is within `2 * margin` chunks of
  a chunk of another same-colour tile, so footprints of simultaneously simulated shards cannot overlap. Deterministic ordering.
  Proof: brute force over 30 random chunk sets (40-200 chunks in a 61x61 area, margin 1-3, tile 2m+1..2m+3): every chunk in
  exactly one shard, every cross-shard pair in one phase more than `2*margin` apart (Chebyshev); input order does not matter;
  negative coordinates handled.
* `connectedShards(active, margin)`: components of the within-`margin` graph, for islands of activity (two players far apart).

## Not done, and exactly what is left

1. **Nothing runs shards in parallel: blocked.** Same wall as #16: chunks are shared mutable data (refcounts are atomic, contents are not safe to share; docs/MULTITHREADING.md)
   (`server/pumpkinlib.aowl`). Sharding changes who may touch which chunk, but every shard still touches the same refcounted
   `World`/`Level` objects (entity list, block event queues, `unsentBlockChanges`, lighting queues, the block log, the body
   manager's global collision-provider registry). Needs from ENGINE: atomic refcounts (or shard-owned heap), thread-safe
   allocation, and a decision on the tick thread's role as the only owner of network sends.
2. **Cross-shard work needs a defined mailbox.** Entities crossing a tile border, explosions, fire, fluid and redstone that
   straddle a border, and block bodies spanning tiles: plan = run the phases' shards, then a single-threaded "border phase"
   over chunks within `margin` of a border (the planner can emit those: chunks whose Chebyshev distance to another tile is
   <= margin). Not written: add `borderChunks(plan)` and per-system declared margins (entity AI 16 blocks = 1 chunk, fluid 1,
   redstone 1, fire 1, explosions power/16).
3. **Per-system margins, vanilla ordering semantics.** Vanilla ticks in a defined order within a tick (block events, then entities
   by list order); a phase plan changes inter-entity ordering across shards. Needs an explicit statement and a determinism test
   against the scene suite before use.
4. **Measure first.** Profile with `/profile` under load (many mobs spread over regions) to find whether the entity or the
   world tick dominates; do not shard a cost that is dominated by chunk IO or networking (both single-owner here).
5. **Player-facing risk.** Needs user approval before any parallel tick is enabled by default; first gate behind a config flag with
   shard count 1 equal to today's loop.
