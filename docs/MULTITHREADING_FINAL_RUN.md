# Multithreading final run: results and open failures

Build under test: `C:/m/int_all.exe` (branch `mt-int`, HEAD 72b6f48 plus the later local commits; all thread-safety fixes, reserved Urgent worker,
teleport-confirm fix, solver job wiring). Comparison build: `C:/m/int_final.exe` (earlier, 15:35). Environment: one Windows machine, one server at a
time, fresh world and random seed per run unless stated. Everything below was measured on 2026-11-18/19; counts are runs, not statistics.

## Full run (`sh tools/run_scenarios.sh C:/m/int_all.exe all`)

| Configuration | pass | fail | failing scenarios |
|---|---|---|---|
| defaults (every gate off) | 13 | 6 | worldedit_more, worldedit_wand, fluids_finite, packs_live, datapack_tick_live, create_live |
| gates on (MC_THREADS=4 MC_CHUNK_WORKERS=4 MC_NET/PATH/LIGHT/EROSION/SOLVER_WORKERS=1) | 14 | 5 | fluids_finite, packs_live, invite_live, datapack_tick_live, create_live |

Expected / known: packs_live and datapack_tick_live fail by design; worldedit_more, worldedit_wand and fluids_finite have peer-side fixes pending
that are not in this exe.

## create_live: not a regression of the multithreading work (not root-caused)

The bot output of every failing run shows the same first symptom: `/create scan` reports `1 components, 1 sources, 0 consumers` (only the motor)
and `/create speed <gearbox>` answers `No kinetic component reached`, although the bearing command succeeded (25 blocks). The scan walks
`scanWorld` from the motor and asks `stateIdAt(world, x, y, z)` for the copper_block gearbox stand-in at (6, 219, 6); in the failing runs it is
not classified as a gearbox. A passing run reports `3 components, 1 sources, 1 consumers` and `turned -90.0 per 25 ticks`.

Runs of `create_live` solo (`SCENARIO_DIR=C:/m3/<tag> PORT=2612x`), same scenario, same coordinates each time:

| Build | Env | Result |
|---|---|---|
| int_all | defaults | FAIL x3 (status unreadable / scan 1 component) |
| int_all | MC_CHUNK_WORKERS=0 only | FAIL x1 (scan 1 component) |
| int_all | MC_THREADS=0 only | FAIL x1 ("No bearing: no movable block in the box": failed before the scan) |
| int_all | MC_THREADS=0 MC_CHUNK_WORKERS=0 | FAIL x1 (turned 0.0) |
| int_all | every MC_*_WORKERS=0 and MC_THREADS=0 MC_CHUNK_WORKERS=0 | PASS x1, FAIL x2 |
| int_final | defaults | FAIL x1 (turned 0.0) |
| int_p4 (Nov 18 12:20, earliest int build) | defaults | FAIL x1 |
| int.exe (21:21), int_resv (19:27), int_tp (21:16) | defaults | FAIL x1 each |
| srvfinal.exe (Nov 17 14:13, before the thread work) | defaults | FAIL x1 (scan said 3 components, then status unreadable) |
| srv_create.exe (Nov 17) | defaults | did not start (no minecraft-server.toml written), not usable |

Reading: it fails on every build I could run, including a Nov 17 build that predates all gates, the reserved worker and the solver wiring, with all
gates and worker counts off, and with them on. The one pass (1 of 4 runs with everything off, 1 of ~14 overall) shows it is not deterministic.
So it is **not attributable to the solver job wiring, the reserved worker or the gates**. It is also **not explained**: the intermittent piece is
the world read of the gearbox block that `/setblock` just placed (or a scan before it is visible), and `docs/MULTITHREADING.md` records earlier
solo passes of `create_live` that this machine did not reproduce today. Commit 137bed8 introduced the scenario with the note "(unverified live)".
Next step for the owner of `src/mods/create`: print `stateIdAt` at the gearbox position in `scanWorld` in a failing run. No src patch is
proposed because no src root cause was found.

## invite_live: not reproduced

Gates-on environment, `int_all`, solo: PASS x3. Defaults: PASS x1. `int_final` with gates on: PASS x1 (5 of 5). In the full gates-on run the
server log shows `/invite decode notacode!!` as the last command executed, i.e. the failure was in the check right after the garbage code (the
bot waits 1.5 s for a reply, `_reply(s, 'invite decode notacode!!', 1.5)`): consistent with a reply timeout under full-suite load.
The original failure message was not kept; this is an inference, not a demonstration. Treat as flaky until it reappears with its message.

## Two-world scenarios

`tools/run_dim_threads.sh` failed on the bot, not the server: `a stack with 1+0 components: this bot does not read them (while handling play
packet 0x64)`. Packet 0x64 is entity equipment (slot byte, stack with the `damage` component, id 3). `tools/mcbot.py` now reads the
`max_damage`/`damage` components (one varint each) and skips an equipment packet it cannot size. Second bot-side issue: bot DimA took
`online_before` while DimB was not yet logged in and then failed `the server still counts the player` because DimB was online; the check now
accepts a status whose sample no longer contains the bot's own name.

Results with the fixed bot (`int_all`; gates: MC_THREADS=4 MC_CHUNK_WORKERS=4 MC_DIM_THREADS=1 MC_DIM_PLAYERS_MULTI_WORLD=1 MC_THREAD_ASSERT=1; the server
printed `dimtick: dimension threads on`):

| Run | gates | result |
|---|---|---|
| run_dim_threads, 2 bots | on | PASS x2 (both bots PASS; server alive afterwards) |
| run_dim_threads | defaults | PASS x1 |
| run_dim_portal | defaults | PASS x1 |
| run_dim_portal | on | PASS x2, FAIL x1 (`timed out waiting for the respawn back to the overworld (trip 0)`; no server-side error or assert line; the first gate-on run, before the bot fix, which does not touch this path) |

(Superseded by the 10+10 table below: gates on fail 5 of 10.) The gated portal failure is real in the sense that it happened once in three gated runs and zero of one default run; with those counts it is
neither shown to be gate-caused nor shown to be flaky-at-baseline. It needs more runs per configuration.

## dim_portal gated failure: 10 + 10 interleaved runs (Nov 19)

`sh tools/run_dim_portal.sh C:/m/int_all.exe`, 10 runs gates on (MC_THREADS=4 MC_CHUNK_WORKERS=4 MC_DIM_THREADS=1 MC_DIM_PLAYERS_MULTI_WORLD=1
MC_THREAD_ASSERT=1) alternated with 10 runs on defaults (gate, def, gate, def, ...), one server at a time, ports 26150-26162, free memory 5.6-10.5 GB
before each run. Per-run directories and outputs are in C:/m3/dp_gate_N and C:/m3/dp_def_N (+ .out).

| Config | PASS | FAIL | Failure text |
|---|---|---|---|
| gates on | 5 (runs 1, 2, 4, 6, 10) | 5 (runs 3, 5, 7, 8, 9) | all 5: `timed out waiting for the respawn back to the overworld (trip 0)` |
| defaults | 9 | 1 (run 7) | `the frame interior is not a nether_portal block (state 10)` (different, earlier failure: the overworld frame did not light; the trip never started) |

Timings: gated passes finished the scenario in 23.5-27.7 s; default passes in 36.3-47 s (the bot's "back in the overworld" lines, where
printed, were 6.5-10.0 s on defaults, 2.5 s in the one gated pass I inspected). Gated failures: the bot arrives in the nether after 0.8-2.1 s, sees the
destination portal (`server says nether_portal: True`), walks in (`/tp` to the cell's side), and then no respawn ever comes; scenario times out at ~63-65 s.

Server logs: zero `owner guard` / `raised` / assert / violation lines in all 20 runs; the only `dimtick` line is `dimtick: dimension threads on` in
the gated runs. The server gives no error at all, but all 5 gated failures show the same pattern: the server log goes quiet right after PortalA's
last `/tp` (the walk into the portal). Server `setblock` lines executed: 92, 95, 92, 98, 101 in the failed runs vs 394 in a passing run (companion PortalB
should issue ~90 s of setblocks); the companion bot's keep-alives drop from 12 (pass) to 3-4 (fail); and the post-run `stop_server`
login (`SERVER NOT ANSWERING after bots`) fails in exactly those 5 gated runs and in no other run (15 of 15 others: `SERVER ALIVE`). So the
failed gated runs are not "the respawn arrived late": the server stops serving commands and new logins around the time the portal transfer would be
processed.

Hypothesis (not proven): with MC_DIM_THREADS on and two players in different dimensions, the portal transfer of PortalA out of the nether (queued
by postCross) stalls or deadlocks the tick, e.g. a lock/join between the dimension job and the main tick that the transfer touches. A one-tick-late
transfer or the teleport-confirm race would not stop the companion's commands and the login path, so that explanation fits the data poorly. Nothing
here shows which lock; the next step is a stack dump (or the dim job/join timings, not exposed in the log of this build) of a hung gated server.
The one default failure is a separate, earlier flake (portal frame not lit) and does not reach the transfer.

## Honesty notes

* Ports: my first dim/portal runs used 26140-26170, outside the 2612x-2613x range I was given; later ones used 26121-26129. A server of mine
  (port 26180, from a batch I aborted) kept running until its bots finished, then was stopped with the `stop_server` scenario. No process that
  I did not start was touched.
* No src change and no rebuild were made.

## dim_portal gated hang: ROOT CAUSE PROVEN (Nov 19): lost wakeup in jobpool.submitLane

Method: loop of gated `run_dim_portal.sh C:/m/int_all.exe` runs with a watcher; when neither bot log grew for 40 s the watcher attached
`gdb -p <server pid> -batch -ex "thread apply all bt 25"` and detached (files in docs/dim_portal_hang/, driver2.sh, summaries). Prebuilt exe only,
no src change, no rebuild. (A first watcher keyed on "server.txt quiet 15 s" gave one false positive on a passing run, kept as
g1_pass_run_idle_stacks_false_positive.txt: a healthy server is idle there.)

Stacks of the hung server (identical in 3 of 3 caught hangs: g2, a2, a3):
* Tick thread (thread 1): `serverLoop > stepTicker > tick > tickWorlds > tickWorldsThreaded > runDimTicks > applyOutboxes > (portal transfer closure,
  portalmod.tickPortal) > getPortalDestination > findSafeLocation > fetchChunk > generateChunk > pumpUntil > waitCompleted > SleepEx`.
  I.e. the join phase already finished; the queued CrossPortal message runs on the tick thread, needs a destination chunk, generates it with
  `pumpUntil`, and pumpUntil loops forever because `executor.inFlight > 0` (`waitCompleted(1)` = Sleep(1), then retry). This is why everything else stops
  (no tick, no keep-alives, no logins) while the process is alive and quiet.
* All 5 pool threads (3 general + 1 reserved Urgent-only + ... as created) are in `workerMain > waitSysCond` (SleepConditionVariableCS): idle, asleep.
  No lock holder, no cycle between dim jobs and the tick: it is not a deadlock, it is a lost wakeup.
* gdb memory dump of the JobPool object (g2_jobpool_memory.txt): lane Normal `lq[1]` has 1 queued job, `lh` = {0,0,0} (not taken), `pendCount` shows 1 pending
  for the chunk-gen owner, while all workers wait on the condition. A queued Normal job that no sleeping worker picks up.

Mechanism: `dimtick.dimPool` calls `addReservedWorkers(p, 1)` (a worker that takes only the Urgent lane) and all workers share ONE condition variable
`p.wake`. `submitLane` ends with a single `signal(p.wake)`. When the chunk system submits a Normal job, the one signal can wake the reserved worker; it
re-checks `p.lh[lnUrgent] >= len` (nothing for it) and sleeps again, the signal is spent, the Normal job stays in the queue, and the general workers
that could run it keep sleeping. The only thing that would later wake them is another submit; the tick thread is itself blocked in the pump waiting
for this very job, so none comes. Only exists when a reserved worker exists = only with MC_DIM_THREADS=1 and the gate on. Probability per Normal submit is
about 1/(idle workers), hence intermittent; a portal transfer into a not-yet-generated nether chunk with otherwise idle pool makes it likely (one
chunk, one signal), which is why it hits right after PortalA's walk in. The 19-minute soak passed because chunks were mostly loaded then.

Counts (tick-thread stack identical in each hang): run 1 (assert on) 1 pass (g1), then g2 HANG; then 12 interleaved runs:
* gate on, MC_THREAD_ASSERT unset (a1..a6, MC_CHUNK_WORKERS=4): 2 hangs / 6 (a2, a3), 4 pass. So the assert gate is not involved.
* MC_CHUNK_WORKERS=0 with the gates (b1..b6): 0 / 6, but the gate refuses there ("dimtick: dimension threads refused: no worker threads"), so those runs are
  the gate-off path; consistent with the cause (no reserved worker, no hang) but not an independent test.
* My own gated runs with MC_CHUNK_WORKERS=4 and a watcher: g1 pass, g2 hang, a1..a6 = 2 hangs: 3 hangs in 8 runs, all 3 with the same stack. The earlier 10+10 table
  (5/10 gated hangs) was not re-run.

Fix (not applied, docs/patches/jobpool-lost-wakeup.patch, `git apply -p1`): in `submitLane`, `broadcast(p.wake)` instead of `signal` when `p.reserved > 0`
and the job is not on the Urgent lane. Smallest change; cost is a few spurious wakeups per Normal submit only when dimension threads are on. Cleaner
alternative: a second condition variable for the reserved workers (signal each per lane). Not verified by a run: no rebuild was possible. Verification
needed after a rebuild: loop the gated dim_portal 10x, expect 0 hangs.
