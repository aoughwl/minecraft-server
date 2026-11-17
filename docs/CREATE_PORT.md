# Native Create port on the body system

Goal item: `GOAL-server-physics.md` Phase 3 #1 (native Create port as a server mod on bodies) and Phase 2 "rebuild kinetic on the body system".
This page says what the first increment **is** (all of it runs and is tested), the decisions behind it, and EXACTLY what is left and what blocks it.
Where this page and the code disagree, the code is right. Client side: `docs/CREATE_KINETIC_CLIENT_REBUILD.md` (design only).

| Part | Status |
|---|---|
| Kinetic network model: shafts, small/large cogwheels, gearbox, clutch, gearshift, source, consumer; speed (rpm) and stress (su); network solving with direction and ratio propagation, jam and overstress detection | **real**, pure, 44 checks (`src/mods/create/kinetic.aowl`) |
| Rotating contraption: a kinematic body turned about a pivot, exact poses, consistent velocity fields, riders carried | **real**, pure part 30 checks (`contraption.aowl`), world part in `createworld.aowl` |
| Bearing: network speed -> body rotation, the contraption is ONE body on the existing body manager (`kinematic` flag) | **real** (in-memory world test) |
| `/create` debug command (`motor`, `bearing`, `release`, `scan`, `speed`, `status`, `clear`) | **real** (command text tested; tree registration compiled only with the whole server) |
| Persistence of motors, bearings and the kinematic flag | **not done** (item 1 below) |
| Real Create blocks, items, recipes | **blocked** on the registries (item 2) |
| Belts and chains, mechanical press, mixer, drills/saws/deployers, fluids, schematics | **not done**, specified below |

## 1. What exists

All paths relative to the repository root.

| File | What |
|---|---|
| `src/mods/create/kinetic.aowl` | the model and the solver. **Pure**: no world, entity or body import, so it can be compiled into a Jester client mod from the same source (phase 1 item 2, shared packages). |
| `src/mods/create/contraption.aowl` | pure geometry of a body turned by a machine: `spinBody`, `standsOn`, `carryPoint`, `yawDeltaDeg`. Imports only `physics/body` and `physics/integrator`. |
| `src/mods/create/createworld.aowl` | the world side: stand-in block table, flood scan, registered motors and bearings, `createTick`, rider carry. |
| `src/mods/create/createcmd.aowl` | `/create ...` (op level 4), wrapper around `createExec`. |
| `src/mods/create/{kinetic,contraption,createworld}test.aowl` | the tests; `tools/run_create_tests.sh [kinetic contraption createworld]` builds and runs them (own nimcache under `C:/m`, no build lock, never installs anything). |
| `src/server/body/bodyentity.aowl`, `bodymanager.aowl` | `BodyEntity.kinematic`; `tickBodies` skips kinematic bodies (no gravity, no sleep, no auto settle); `bodyPoseChanged` (record pose, queue ONE state event, checkpoint); `isBodyCell`, `parseBox`, `relCoord`, `parseFloatSafe`, `parseIntSafe`, `f2` exported. 13 added lines, no behaviour change for free bodies. |

Wiring that still needs a whole-server build to prove (see section 5): `createcmd.registerPermission` / `initCommandTree` in
`src/server/command/default_dispatcher.aowl` (next to `bodycmd`) and one call `createTick(self)` after `tickBodies(self)` in
`src/server/servermod.aowl:tickWorlds`.

### 1.1 The kinetic model (`kinetic.aowl`)

* **Ports.** A component exposes shaft ends toward the six neighbours (direction index 0 `+x`, 1 `-x`, 2 `+y`, 3 `-y`, 4 `+z`, 5 `-z`, opposite = `d xor 1`) and,
  for cogwheels, the RIM (port 6). Shaft/cog/clutch/gearshift: both ends of their axis. Gearbox: all six. Source/consumer: one end (`facing`) or the axis.
* **Links.** AXIAL (component A has port d, the neighbour has port d xor 1): ratio +1. MESH (two cogwheels on one axis): small-small orthogonally adjacent in the
  plane, small-large diagonally adjacent in the plane; speed_b = -speed_a * teeth_a / teeth_b (8 and 16 teeth). Large-large is not modelled (see 4).
* **Inside a component.** Shafts and cogs pass +1. Clutch passes only while engaged. Gearshift reverses while engaged. Gearbox is **entry relative**: the port
  opposite the entry turns the same way, every other port the other way (this is how Create's `DirectionalShaftHalvesBlockEntity` behaves, from memory).
* **Units.** Speed in rpm, signed (right hand rule about the component's +axis). `rpmToRadPerTick(rpm) = rpm * 2 pi / 1200`. Stress in su: a source offers
  `capPerRpm * |rpm|`, a consumer demands `impactPerRpm * |rpm|` at ITS OWN speed (so a speed-up gear raises the demand, as in Create). Speeds cap at 256 rpm.
* **Solver.** Breadth first search over (component, port) vertices from every source not yet reached, in node order. Every cycle edge and every extra source in
  a network is CHECKED against the speed already assigned: a mismatch **jams** the network (speed 0, `nsJammed`, a reason naming the two cells and the two
  speeds). Then demand > capacity makes it **overstressed** (speed 0, `nsOverstressed`, capacity and demand reported). Unreached components: speed 0, network -1.
  Deterministic: insertion order of the graph does not change any speed (tested).

### 1.2 What the tests prove (and would catch)

| Check | A mutant that must fail it |
|---|---|
| gear train 16 rpm -> large cog -8 -> small +16; small/large ratio at -48 rpm = +96 | wrong sign or wrong tooth ratio in `meshes` |
| two motors against each other, 16 vs 32 rpm, a motor on a meshed cog turning the wrong way: `nsJammed`, all speeds 0, reason given; the right-way motor runs | removing the cycle/source consistency checks |
| a ring of 4 small cogs closes, a ring of 2 small + 2 large cogs closes (-0.5 * -2 * -0.5 * -2 = 1) | a wrong ratio or a missing edge check |
| demand 256 su vs capacity 256 su runs, 272 su stops; both scale with speed (8 rpm: 128 / 136) | `>` vs `>=`, or capacity not scaled by speed |
| gearbox: straight output same way, both perpendicular outputs reversed; clutch, gearshift | entry-relative rule |
| platform after 75 ticks of 8 rpm is exactly half a turn (cell at +x is at -x); after 150 ticks the identity; quarter turn takes +x to -z; surface velocity equals omega x (p - pivot) for a centred and an off-centre pivot | `spinBody` formula, quaternion order, velocity fields |
| a rider at radius 2 is carried 75 ticks: ends at (10.5, 65, 12.5), radius 2.0 to 1e-9, still standing, fixed in the body frame; a control that is not carried stays at 14.5; hovering and off-platform points are not carried | carry missing, tangent-step carry (drifts outward), wrong standing test |
| world: motor -> gearbox -> bearing gives -8 rpm; yaw after 1 and 37 ticks to 1e-9; the dirt marker moves toward +z; the platform does not fall (no gravity, no auto settle); an item standing on it is carried to (22.882, 62, 25.676) +- 0.01 in 60 ticks, while the same run with the carry switched off leaves it > 3 blocks away | carry, direction, kinematic skip in `tickBodies` |
| world: a second motor opposing the first jams the network and the platform stops within 20 ticks; reversing it runs again with doubled capacity; cutting the gearbox idles the bearing | solver + `rescan` + `createTick` |
| world: release at exactly a quarter turn puts 25 blocks back, the dirt marker from (26,61,24) at (24,61,26) | rotation direction and `settleBody` mapping |

## 2. How it is built on the body system

* A contraption is **one `BodyEntity`** created by `assembleCells` (journaled, one all-or-nothing edit, block entities kept) with `kinematic = true`.
  The manager never integrates it. The bearing sets its pose each tick (`spinBody`) and calls `bodyPoseChanged`, so the existing network feed
  (`bodysync`: `jester:bodies` STATE with `angvel`, `block_display` fallback), the collision provider, `/body info` and the replay recorder work unchanged.
* Velocity fields stay consistent with the motion (`angVel = axis * dAngle`, `vel = angVel x (com - pivot)`), so
  `vel + angVel x (p - com) = angVel x (p - pivot)` and the provider's `surfaceVelocityAt`, the client's `bodyRideCarry` (omega x r) and mob bumping are right.
* **Riders.** Non-player entities whose feet rest on a top surface (`standsOn`, tolerance 0.05) are moved by the same EXACT rotation through `moveEntity`
  (walls still stop them) and turned by the yaw delta. Players: position is client authoritative, so the Jester client carries itself
  (`aoughwl.bodies` `bodycollide`/`vxbodyride`); a vanilla client riding a contraption is the open movement-authority item (4).
* Stopping: `/create release` (or the bearing going away) calls `removeBody` = nearest of the 24 grid rotations, nearest integer position, free spot search,
  states mapped through the rotation (`mapStateRot`). Stop at a multiple of 90 degrees for an exact return (tested).

## 3. Remaining work, in order, each with its blocker

1. **Persistence (small, unblocked).** Motors, bearings and `kinematic` are in memory. The body journal saves the pose but not the flag, so after a restart a contraption
   comes back as an ordinary free body (falls, lands, may fail to settle if not axis aligned). Needed: a `kinematic` + bearing-binding field in `bodyjournal.aowl`
   (format version bump), a per-world `create.dat` for sources and bearings, replay on first sight of the world (`ensureJournal` hook), bearing restore after
   `resolveReplayed`. Test: crash scenario like `bodytest`'s `gTestCrash`.
2. **Real blocks and items (blocked: registries).** Today a component is a vanilla stand-in chosen by a data table (`stripped_oak_log` shaft, `stripped_birch_log` small
   cog, `stripped_dark_oak_log` large cog, `copper_block` gearbox; motors and bearings are registered by command). Real Create needs the planned block/item/block-entity
   registries (`docs/REGISTRIES.md`, phase 1 item 4): custom ids synced in configuration, stable per-world ID map, block entity data (speed, network id, stress).
   Without them a vanilla client cannot even show a shaft; with them a Jester client gets models from the client mod rebuild.
3. **Server-to-client speed feed (blocked: capability + client mod).** New channel `create:kinetic` (draft in the client design doc) and a `kinetic` capability bit in the
   handshake; the server already knows every node's speed after `rescan`. Needs `bodysync`-style per-viewer interest and the client mod from the rebuild doc.
4. **Gear rules to verify against the real mod (UNVERIFIED, from memory).** Large-to-large meshing (Create meshes large cogs on perpendicular axes; not modelled);
   gearbox output signs for three simultaneous ports; Create's overstress handling (this port stops the whole network, Create keeps nodes with speed 0 and a
   visual); stress numbers (`ImpactMechanicalPress 8`, `Mixer 4`, `Bearing 4`, `CapPerRpmCreativeMotor 64`, water wheel 32/rpm) are DEFAULTS, to be loaded from a data
   file (content packs, `docs/PACKS.md`) so a pack can override them. The Create jar was not available offline; compare with the source before trusting.
5. **Belts and chains.** A belt is a long edge between two shaft ends: ratio from the two pulleys' radii, length n, optional slope; items ride the belt (a moving
   item carrier along a polyline). Model: extend `Edge` with arbitrary endpoints (`beltLink(a, b, ratio)` in `buildEdges`), same solver. Items on belts: a belt
   is a kinematic surface like a contraption but linear: reuse the rider carry with a translation (`carryLinear`), and item entities are re-spawned on the next
   belt segment; or keep items as belt data (Create's `TransportedItemStack`) and draw them client side. Needs: block entity data (registries) and a path/segment
   structure with save format.
6. **Mechanical press and mixer.** Consumers with a processing state machine: press (8 su, 512 su at max speed in Create; compresses an item under it, needs a basin
   or belt below), mixer (needs a basin and a heat source). Needs: recipes (`recipe.aowl` has a manager; Create's recipe types `pressing`, `mixing`,
   `compacting`, `milling`, `crushing`, `cutting` must be added as data), item entities or belt items as inputs, a processing timer per consumer (a block entity),
   `speed -> progress` (rpm scales the time), output spawn. Blocked on: block entities (item and fluid inventories) from the registries; basin = a block entity with
   inventory and tanks.
7. **Fluids.** Pipes (graph with pressure, flow), pumps (a kinetic consumer producing pressure by speed), tanks, spouts, basins. A fluid network is the same kind
   of graph problem as the kinetic one (solve flow per tick with budget); phase 3 item 9 "finite fluids" is the prerequisite for world fluids. Blocked on: fluid
   storage in block entities, a fluid registry, the finite fluid system.
8. **Schematics.** `.nbt` (structure format) read/write and placement with the WorldEdit clipboard (`src/server/worldedit/wecore.aowl` `Clip`, `weworld.aowl`
   `bulkedit.placeVolume`); a schematic table/cannon item that needs the item registry; blueprint rendering on the client (ghost blocks). Mostly unblocked
   on the server side: NBT codec exists (`src/nbt`), placement exists (`placeVolume`). A `/create schematic load|place|save` debug increment is the first step.
9. **More contraption parts.** Mechanical piston and pulley (translation along an axis: a kinematic body with `pos` driven by speed; the same pieces with `spinBody`
   replaced by a translate), rope pulley, gantry carriage, minecart/carriage contraptions with movement behaviours (drills, saws, harvesters, deployers: block
   break/place from a moving body, which needs the body-to-world block query of `bodyworld`), chassis and glue (which blocks attach: a flood fill by glue
   faces, today `addBearing` takes a box). A contraption that touches the world (collides with terrain, drills) needs body-vs-world contact that the integrator
   does not do for kinematic bodies (it treats them as infinite mass): stop the bearing when blocked, like Create does.
10. **Players on contraptions with a vanilla client.** Needs the movement authority spec of BODIES-DESIGN.md (T6): server-side relative movement
    (`carry` the player's expected position inside the movement check, a velocity/teleport packet per tick). `createworld` deliberately skips players today.
11. **Budgets.** `rescan` is a flood plus a solve every 10 ticks per world with `MaxScanNodes = 4096`; fine for debugging, not for a base with thousands of
    shafts. Make networks persistent (incremental on block change events: `bodymanager.onBlockChanged` style hook), solve per network on the worker pool.
12. **Whole-server proof of the wiring**: build, `/create motor`, `/create bearing`, watch a bot receive STATE frames with `angvel` (`tests/body_net_scenario.py`
    pattern) and check `jester:bodies` decoding. Not done in this increment (build lock and time); see the report in `PROGRESS.md`.

## 4. Decisions worth knowing

* **Kinematic flag, not a new body kind.** A contraption must be a body so that networking, collision, journal and replay come for free; the cost is one `if` in
  `tickBodies`. The alternative (own entity kind) would have duplicated all four.
* **Exact rotation, not integration.** `spinBody` rotates by the full angle each tick (a quaternion product and a Rodrigues rotation of the position) instead of
  `integrateOrient`; over 150 ticks the error is below 1e-9 and a full turn returns the identity.
* **Speed convention.** Positive = counter-clockwise seen from the +axis end of the component; a bearing about +y with positive speed turns counter-clockwise seen from
  above, which is a NEGATIVE Minecraft yaw change (`yawDeltaDeg`).
* **Stand-in blocks are a data table**, not name heuristics scattered around: `classify` is the single place.
* **No Create code was read or copied.** Rules are from memory of the mod's behaviour and flagged UNVERIFIED above.
