# Physics wiring: climate, fire, explosions, erosion

The pure models in `src/physics` (climate, fire, blast, erosion, windfield) are connected to the real server by the glue in
`src/server/physwire` (and, for explosions and collapses, `src/server/body/trigger.aowl`). Every feature is **off by default**, opt-in per world,
and costs one bool/string test per tick while off, EXCEPT the collapse triggers, whose default is `structures` (tree felling and player built
structures; set `JESTER_PHYSICS_TRIGGERS=off` or `/body triggers off` for vanilla behaviour). Commands need op level 4.

| Feature | Setting (file in `<world>/aowlmony/`) | Env default | Command |
|---|---|---|---|
| Climate feed | `climate_feed.txt` = off / on | `JESTER_CLIMATE_FEED` | `/climate on\|off\|status\|at\|override <vx> <vz>\|override off` |
| Fire spread | `physics_fire.txt` = off / on | `JESTER_PHYSICS_FIRE` | `/fire on\|off\|status\|ignite [x y z]` |
| Collapses, tree felling, explosions | `physics_triggers.txt` = off / **structures** (default) / full | `JESTER_PHYSICS_TRIGGERS` | `/body triggers off\|structures\|full\|status`, `/explode [x y z] [power]` |
| Erosion | none: a job you start | none | `/erosion run [radius] [seed] [wet]\|status\|cancel` |

A setting file wins over the environment variable; the environment variable is the default for worlds with no file.

## Climate feed (phase 3 item 8)

With `climate_feed = on`, every 20 ticks the server samples `climate.aowl` at the first player of the overworld (the spawn when nobody is
online), dated by the world's time-of-day counter (so `/time set`, `/time add` and sleeping move the date and so the **season**), and with the
**real** rain and thunder levels (`world.weather`):

* the server's own wind field (`windfield.setWeatherProvider`) gets real rain/thunder plus the climate wind, so bodies, fire and the collapse
  triggers see the same wind;
* the `jester:wind` stream gets `baseSpeed` (the synoptic pressure-gradient wind, at most 20 b/s) and `baseYaw` (the direction it blows toward,
  0 = +Z, pi/2 = -X) as an UPDATE whenever they move by 0.1 b/s or 0.03 rad; every other parameter stays what the packs / defaults say.

`/climate override <vx> <vz>` pins the synoptic wind (blocks/second toward +x/+z) for tests and events. `off` restores the base parameters.
Pure code and tests: `src/physics/climatefeed.aowl`, `climatefeedtest.aowl`.

## Fire spread (phase 3 item 12)

With `physics_fire = on` a vanilla fire block that took its fire tick skips vanilla spreading and hands the fuel next to it to a `FireSim` of its
region (a 41 x 40 x 41 box, up to 4 per dimension; fires outside every region over the limit stay vanilla). The model spreads by material
(`materials.aowl` flammability, ignitability, mass), wind (`windAtWorld`), rain (real rain level on sky exposed cells) and water. Burnt out
fuel becomes air through `bulkedit.writeCells` (block log cause fire, collapse trigger hook, one client update per section); a fire block is shown
next to burning cells. Vanilla's own rain/fuel survival checks of the fire block remain. `removedCells` need no special path: with
`/body triggers structures` a burnt support is an ordinary block change that dirties its structure.

Limits: burnt state is always air; TNT is not primed by the model; embers and smoke are not displayed; a region is a snapshot (a cell the world
changed meanwhile is skipped); fire does not spread across a region edge.

## Explosions (phase 3 item 13)

Every explosion (TNT, creeper, end crystal, bed, wind charge, minecart, `/explode`) goes through `explosion.explodeBlocks`. With
`/body triggers full` the cells that go come from `blast.runBlast` (vanilla's rays with an energy criterion by material), survivors are cracked
for the following collapse check, heavy fragments become small bodies instead of item drops, nearby bodies get impulses, and the removed cells
dirty the area so the remainder is structurally checked. Drops, particles, sounds and entity damage stay vanilla. Over the 1.5M ops/tick budget
a blast falls back to the vanilla result. `/explode` is new.

## Tree felling and collapses (phase 2 level 2)

With `physics_triggers` = `structures` (the default) or `full`, a block a **player** breaks is a collapse trigger twice over:

* **trees** (`src/server/body/fell.aowl`, pure logic `fellogic.aowl`): on the next tick the logs next to the cut are flood filled (26-connected,
  the `minecraft:logs` tag); a log component with no 6-neighbour of any other structural block (leaves never hold a trunk up) that stays
  inside a 25 x 43 x 25 box is cut loose with the leaves that are nearer to it than to any other trunk, as ONE body (at most 512 cells, else
  the tree stands). It starts turning about the cut face away from the nearest player (else downwind), falls under gravity, lands; then its
  leaves break into their loot drops (material table: the soft class) and the bare logs settle at the nearest grid rotation (lying, axis
  turned) or drop as items. Natural trees are included; stone, dirt and every other non-log block are never felled. In `full` fire and
  explosions fell trees too. Budget: one tree per tick, 6 per burst and one per 10 ticks per dimension, at most 48 live bodies, a 64 cut queue.
* **player built structures** (`trigger.aowl`): the cut dirties its structure, which the structural solver checks (only player built
  cells may fail or fall, see the header of trigger.aowl).

Clients with the Jester `bodystream` capability get the body on `jester:bodies`; vanilla clients see `block_display` entities. Status:
`/body triggers status` (line `tree felling: ...`). Live test: `SCEN_SECONDS=300 sh tools/run_scenarios.sh <exe> phys_fell`.

## Erosion (phase 3 item 14)

`/erosion run [radius] [seed] [wet]` reads the terrain within `radius` (4..48) blocks and 32 blocks above/below the sender, relaxes it with
`erosion.aowl` at 20000 ops per tick (landslides to the angle of repose, slabs that break off become falling bodies), and writes the result
once through `writeCells` (block log cause natural). Seeded (default: the world seed), wetness defaults to the real rain level, volume is conserved,
one job at a time, nothing automatic. `/erosion status` shows cells changed, bodies and skipped cells. A moved cell counts twice in `cells changed` (taken from one column, put on another); slumped soil can leave the job box over an unsupported edge, so catch it with a platform.

## Tests

* pure: `climatefeedtest` (20 checks); `src/server/body/felltest.aowl` (felling logic) and `fellsimtest.aowl` (an oak toppling in the integrator); the model tests `climatetest`, `firetest`, `blasttest`, `erosiontest`, `sh src/physics/run_scenes.sh`.
* live (a headless server and `tools/mcbot.py`): `SCEN_SECONDS=900 sh tools/run_scenarios.sh <server exe> phys_climate,phys_fire,phys_blast,phys_erosion`
  (these four are skipped by `all`).
