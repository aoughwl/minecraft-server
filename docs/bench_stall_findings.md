# Two unexplained bench results: findings (2026-11-18)

Exe `C:/m/int_final.exe` (prebuilt, not rebuilt). Raw runs: `docs/bench_stall_runs.jsonl` (with per-thread CPU samples), gdb stacks:
`docs/bench_stall_gdb_dumps.txt`. Tools: `tools/bench_server.py` gained `BENCH_WATCH=1|gdb` (per-thread CPU/wait sample every 8 s),
`BENCH_IDLE=<s>` (profile an idle server), `BENCH_WARM=1` (tiny far pregen before the profiled one).

## (B) `MC_DIM_THREADS=1` tick-world MSPT 22.5 ms during pregen: EXPLAINED (mechanism confirmed by stacks; fix untested)

* Dim jobs are already submitted on `lnUrgent` (`dimtick.runDimTicks`), so they do not queue behind the Normal lane. The hypothesis as
  worded (queued in lnNormal) is refuted by the code.
* What is true: the pool is non-preemptive and the generation jobs on it BLOCK. gdb attached 6 times during an 8-worker pregen: in
  dumps 1 and 2 the tick thread sits in `runDimTicks` (Sleep(0) drain spin) while ALL 8 workers are in `genJob`, 6 to 7 of them in
  `findOrClaimStructureStart` (a `Sleep(1)` loop waiting for another worker to finish a village start: `jigsaw` / NBT template
  deserialisation). No worker is free, so the Urgent job waits until one finishes, seconds for the first villages.
* Numbers (pregen radius 8, tick MSPT): mean 20-41 ms, p50 1.6-2.5, p95 30-36, max 2.5-4.7 s in 17 of 17 dim runs with workers 4/8 (and 2, 16:
  dim16 mean 29.4 max 4483 ms; dim2 mean 23.2 max 4223 ms). More workers do not help: all of them block on the same claim.
  `pregen inflight 2/8` did not help either (mean 14.7/14.9, max 4539/3274 ms): inflight counts chunks, not jobs, so it does not bound
  busy workers (that earlier looked like a refutation; it is not one).
* Idle server (no pregen), 25 s: dim4 mean 0.70 ms p50 0.064 p95 2.6 max 45 vs cw4 mean 0.05 max 0.17. So the gate alone costs ~0.65 ms
  per tick of dispatch/wake latency, and the multi-second ticks only exist while generation saturates the pool.
* Fill phase (no generation backlog) is unaffected: 24-26 ms in every config.
* Smallest fix: reserve an Urgent-only worker: `docs/patches/reserve-urgent-worker.patch` (`addReservedWorkers` in jobpool, one call in
  `dimtick.dimPool`). The extra thread never takes Normal jobs, so generation throughput is unchanged, and it sleeps on the same condvar.
  NOT compiled or run (no rebuild allowed). Expected effect: tick world back to p50 ~0.1 ms, 20-30 ms tail from scheduler quantum remains
  under CPU saturation. Still to check after rebuilding: the dim job itself may take `lockGen` held by a blocked structure job.

## (A) `MC_SAVE_WORKERS=1` 236-254 s single-tick stalls: REPRODUCED, NOT save-specific, probable cause identified, not proven

* Repro: 1 stall in 4+4+4 more save runs (save4 of port 26045: 348 s tick, fill phase 367 s), and 1 stall in 9 dim8 runs
  (`MC_CHUNK_WORKERS=8 MC_DIM_THREADS=1`, 298 s). 0 stalls in 16 further watched runs. So the earlier "2 of 7" is a ~1 in 10 event that also
  hits other worker-pool configs; it is not specific to `MC_SAVE_WORKERS`.
* Thread samples of both stalls (`thread_samples` in the jsonl): the tick thread burns 100 percent of one core (about 8.2 s CPU per 8.3 s)
  for the whole stall; the 4 (resp. 8) pool workers consume under 50 ms CPU per 8 s sample. The tick thread is the drain spin
  (`compressBatch` / `runDimTicks`: `drainDone` + `Sleep(0)`), the workers are not running jobs, they are asleep. No error line was printed.
* Probable cause: `placement.findOrClaimStructureStart` gives up on an unanswered claim "after 20 s" by counting 20000 iterations of
  `Sleep(1)`. At the default Windows timer (15.6 ms) one iteration is 12-17 ms, so the give-up takes 240-340 s: matches 236, 254, 298, 348 s.
  An unanswered claim exists when the claimant job fails: `generateCached` claims, then `lazilyGenerateStructure` raises, `genJob`
  swallows it ("generation raised") and nothing releases the claim. All workers that then need that start sleep in the loop, the pool has no
  free worker, and every tick-thread join (save compress on lnNormal, dim jobs on lnUrgent) waits for it. That explains why it is
  random, silent, one tick long and affects any worker config.
* Not proven: no stall occurred under the gdb trap (16 runs), and the failing structure was not identified. Direct check after a rebuild:
  print a line when a claim wait exceeds 1 s, and count `generation raised`.
* Fix (backstop plus cause): `docs/patches/structure-claim-deadline.patch`: wall-clock deadline (GetTickCount64, 20 s) and release the claim
  when the claimant raises. Not compiled or run. Longer term: a pool worker should not sleep-wait for another job's result.
* Also noted: the existing `drainDone` spin burns a core per waiting caller; an Urgent/reserved worker and a blocking wait on a
  completion condvar would remove both the spin and the 0.65 ms idle gate overhead.
