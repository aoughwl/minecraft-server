# Phase 3 #16: async lighting and entity ticking

## Shipped (tested, `src/server/sim/workbudget.aowl`, `simtest.aowl`)

A cooperative budgeted job queue: `submit(handle, step)`, `runBudget(q, maxSteps)`, `cancel`. Round-robin over queued jobs, a job
is a non-capturing `proc(handle): bool` (more work / done), so no closure crosses a module. Proved: three 10-step jobs finish
with identical state for budgets 1, 3, 7 and 1000; round-robin order `0 1 2 0 1 2`; cancel keeps the cursor valid. It is the
scheduling half of async work **without threads**: a long relight or a crowd of entities can be spread over ticks.

## Not done, and exactly what is left

1. **Wiring.** No caller uses the queue yet. First candidates, all on the tick thread:
   * lighting: `world/lightingruntime.aowl` `updateLightingRegion` currently relights a whole region at once (bulk edit of 32^3 is
     14 ms of which 7 ms light). Split it into per-section or per-BFS-layer steps behind `runBudget`, keeping the existing
     "dense path equals exhaustive path" comparison as the test. Risk: clients and block updates see stale light for a few ticks;
     needs a "pending light" flag so `bulkedit` can still promise exact results to callers that need them (WorldEdit undo).
   * entity ticking: chunk-ordered entity loop in `worldmod.tick` with a per-tick time cap and carry-over cursor; vanilla
     semantics for the entities skipped in a tick (they simply tick next tick) must be an explicit rule agreed with the user.
2. **Real threads: blocked.** The chunk system shares refcounted chunks with the level and refcounts are not atomic
   (`server/pumpkinlib.aowl`, PROGRESS.md worker-pool notes: the chunk worker pool only works because generation hands over
   finished, unshared chunks). Light and entity ticking read and write live chunks, so they cannot leave the tick thread until
   ENGINE provides atomic refcounts or an ownership-transfer type (move a chunk section to a worker, get it back next tick).
   Needs the ENGINE session and user approval.
3. **Determinism.** Any threaded or budgeted scheme must keep the scene suite goldens (`sh src/physics/run_scenes.sh`) and the
   `lightingruntimetest` equivalence; add a budget=1 vs budget=inf equality test per wired job before turning it on.
