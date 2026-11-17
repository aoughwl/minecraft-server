# Phase 3 #15: mob AI aware of bodies and weather

## Shipped (tested, `src/server/entity/ai/mobawaretest.aowl`)

* **Bodies in pathfinding.** `pathfinder/pathfinding_context.aowl` (`computePathTypeFromState`): an air cell that contains a box
  from any registered collision provider (`entity/collision_providers.aowl`, the seam the body manager registers) is `ptBlocked`
  for path planning. Result: every navigator walks around a body, jumps onto a low one (the evaluator's normal step logic) and
  can stand on one (the cell above a body counts as walkable). Cost with no provider registered: one `len > 0` test per air cell.
  Proof: straight path 11 nodes, with a 7-wide wall body 14 nodes and no node inside the body; unregistering restores 11;
  disabling the hook fails the test ("no path node inside the body").
* **Shelter from rain.** `ai/mobaware.aowl`: `isCoveredFromRain`, `isStandable`, `findShelter` (deterministic nearest covered
  standable cell within 16 blocks and +-2 y) and `SeekShelterGoal` (rain, exposed, not in water, rechecks every 40 ticks, walks
  with the navigator). A block roof and a body roof (a floating deck) both shelter; a body-filled cell is not standable.

## Not done, and exactly what is left

1. **Nobody adds `SeekShelterGoal` to a mob.** Which mobs should shelter (villagers, passive animals; not monsters that like
   rain) is a gameplay decision, and adding the goal changes live behaviour that no live test here has watched. Work: one
   `goalsSelector.addGoal(prio, newSeekShelterGoal(1.0))` per chosen mob type in `mobsmod.aowl` / `passive`, then a live
   scenario (bot, `/weather rain`, see the cow reach the roof). Needs a whole-server build (build.lock).
2. **Moving bodies.** A path is computed against the bodies' positions at that moment; a body that moves into the route later is
   only avoided by the normal movement collision (the provider seam in `entitymod`), so the mob can stall and repath. Work:
   repath when `bodymanager` reports a body whose box intersects the current path (change feed already exists).
3. **Wind and storms.** The goal does not look at `windfield.windAtWorld`; mobs should also leave the lee-less open in a gale and
   avoid walking across a body that is falling (needs the body velocity from `velocityAt`). Small, pure: add a cost term in
   `getMobPenalty`.
4. **Rain exposure uses a 32-cell column scan**, not the heightmap, so a roof higher than 32 blocks above the mob does not count.
5. **Worker threads (the "on worker threads" part of the goal).** Blocked, ENGINE session: path computation reads chunks
   (`World.getBlockStateId`) and entity lists, which are shared mutable objects (the refcounts are atomic, the contents are not: see docs/MULTITHREADING.md). A safe
   design needs a read-only snapshot of the cells around the mob (copy cells out on the tick thread, path on the worker, apply
   result next tick). The `PathfindingContext` already isolates all world reads into `computePathTypeFromState` and
   `hasCollisions`, so the snapshot is one replacement of those two procs. Needs the ENGINE session to provide an atomic
   refcount or a thread-owned snapshot type, plus user approval for a worker pool in the tick path.
