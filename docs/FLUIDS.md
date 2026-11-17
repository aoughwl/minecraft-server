# Finite fluids (phase 3 item 9)

Two levels, like the physics work: a **level 2** that only our server provides, and a **level 1** that any server can get.

## Level 2: server-authoritative, conserved-volume fluids (built)

Optional and **off by default**. `/fluids on|off|status` (op level 3). While off, no fluid code runs and no vanilla water or
lava block is read, written or ticked differently from before: the only cost is one `bool` test per scheduled fluid tick
(`block/fluidseam.gFluidTicksSuppressed`, false).

### The model (`src/physics/fluids.aowl`, pure, tested by `fluidstest.aowl`)

* Sparse grid of cells. A free cell holds `mass` units of one fluid kind (1 water, 2 lava). One cell is full at `cap` = 1024 units.
  A cell under fluid may hold more than `cap` (pressure, `comp` = 48 units of squeeze per layer).
* Integer arithmetic only, fixed processing order (y, then z, then x; cells a budget-limited step did not reach go first next time), so a
  run is reproducible bit for bit.
* Fluid is created or destroyed only by `addFluid` / `adoptFluid` / `removeFluid` / `forgetCell`, which count into `injected` /
  `drained`: `totalMass == injected - drained` holds after every step (tested after each of 400 steps of a random pour/drain/wall-removal
  scene with a budget of 7 cells per step).
* One step, per awake cell: gravity and pressure with the cell below and the cell above (the lower cell should hold `t` if `t <= cap`,
  `(cap^2 + t*comp)/(cap+comp)` if `t < 2cap+comp`, else `(t+comp)/2`; that is the pressure of communicating vessels), then levelling over
  the cell and its free, same-kind, supported horizontal neighbours (only when their masses differ by >= 2 units, so a still pool stops
  changing and nothing flickers).
* Water and lava never share a cell and never flow into each other (`contacts` counts the refused moves). Lava processes every third step.
* Budget: `step(sim, budget)` processes at most `budget` awake cells; an idle pool costs 0 operations.

Measured by `fluidstest` (36 checks): a 6.5-cell pour fills a 1x1 shaft from the bottom and conserves; 10 cells of water settle flat to 8 of
1024 units on a 9x9 floor in a closed world; a U tube filled 20 high in one leg settles to equal surfaces (6 / 6) in 36 steps; a 1-wide leg and a
3-wide vessel share a surface (4 / 4); a pipe rises to the reservoir level by pressure alone (3 / 3); lava needs >= 2x the steps of water (99 vs 30);
identical runs give an identical checksum, also with budget 5; a 25-cell budget still settles and conserves.

### The host (`src/server/fluids/fluidhost.aowl`, `fluidcmd.aowl`)

When on, per world and per tick (hooked into `servermod.tickWorlds`, after `tickTriggers`):

1. every 10 ticks the sections within 2 chunks (+-3 sections) of each player are checked. A section seen for the first time or whose
   `blockVersion` moved for a reason other than the host's own writes is rescanned: exposed or flowing vanilla fluid blocks that are not
   tracked are **adopted** (source = 1024 units, flowing level n = (8-n)/8), tracked cells whose block was replaced by something else are
   forgotten (mass counted as drained), and tracked cells around the section are woken (so a removed wall lets a pool run);
2. every 2 ticks `step` runs with a budget of 600 cells (`/fluids budget`, `/fluids every`);
3. changed cells are rendered back into vanilla states (level from mass, `falling` for a stream cell, air under 1/16 of a block: such a damp
   film stays in the model so volume is conserved but is not shown) and written with ONE bulk edit (`bulkedit.writeCells`: one heightmap
   pass, one multi-block update per section, one light pass; no plugin veto, no neighbour updates, no block log).

The host only ever treats **air and fluid** as free: any other block is a wall, so water never breaks plants, torches or redstone. Vanilla
fluid ticks (scheduled and random) are skipped while the host is on, otherwise vanilla would spread blocks the model does not know.

Tested on the real world code in `src/server/fluids/fluidhosttest.aowl` (in-memory world, 41 checks) and live by the scenario
`fluids_finite` (`sh tools/run_scenarios.sh <exe> fluids_finite`): off = vanilla flow; on = four stacked sources over a 3x3 basin fall and fill
it, the sources are gone, all nine basin cells show level offset 4 (4 x 1024 units over 9 cells = 455 each = 4/8), nothing crosses the rim and
`/fluids status` shows no drain; off again leaves the blocks. (The status totals also include natural water adopted around the bot, so they are not asserted.)

### Known limits (honest list)

* The model is in memory only: after a restart the rendered blocks are adopted again, so a compressed or falling cell comes back at its
  rendered volume and damp films (< 1/16 block) are lost.
* Buckets are not hooked: a placed source is adopted at the next scan, a scooped one is forgotten at the next scan.
* Water meeting lava does not make obsidian or cobblestone (they only count as `contacts`).
* Oceans are finite once the model touches them: only exposed cells near players are adopted, so an ocean next to a pit loses a thin top layer
  locally; the interior stays inert vanilla blocks and acts as a wall to the model.
* The horizontal levelling threshold leaves residual gradients of up to 1 unit per cell (a pool surface is flat to well under 1%).
* Cells of an unloaded chunk are dropped (their blocks stay as last written) and are adopted again when the chunk is scanned.
* Only the dimension's loaded area around players is looked at; a fluid far from every player does not move.

## Level 1: what a client-only version could do (any server, visual only; not built)

A client mod cannot change what the server believes (water the server thinks is a full source stays a source; entities swim by the server's
rules), so a client-only finite fluid can only be a **rendering** layer:

* Smooth surface heights: for every water block the client already knows (levels 0..8 from the block state), draw the surface at the
  interpolated height of its neighbours instead of the 8 steps, so pools look level and edges ripple slightly (a pure function of block
  state, no server data).
* Local conservation illusion: when the client sees water level states change (a flow front, a bucket), animate the transition over a few
  ticks (height lerp) instead of popping, and drain/fill the visual volume of a pool at the same rate (`dV/dt` from the change of the sum of
  visible heights), so the surface moves continuously.
* Waves and wind from the existing `aoughwl.wind` field: a deterministic height offset of `A * sin(k.x + w t + phase(seed, x, z))` scaled by
  the wind speed and the fetch (open distance) of the cell; zero in enclosed cells.
* Splash particles where falling water (`level 8`) hits a surface; bubbles and fog by depth.
* What it cannot do: change flow, make water finite, move water that is not already moving, or affect hitboxes and swimming.

Level 1 has no protocol work and no server requirement; level 2 (above) is the server-authoritative one. The client can detect level 2 with a
capability (not added yet: there is no wire format for fluid state beyond ordinary block updates, which already carry everything level 1
needs).
