# Rebuilding `aoughwl.kinetic` on the `aoughwl.bodies` service

**DESIGN ONLY.** Nothing in the client was edited or rebuilt for this page (the game may be running). It describes what to change in
`Desktop\jester_data\mods\aoughwl.kinetic` and its neighbours once the server side (`docs/CREATE_PORT.md`) is on a whole-server build. Everything
named here was read in the files on 2026-11-17; "NEW" marks what does not exist.

## 0. What `aoughwl.kinetic` is today

A 1217-line library mod (`mod.json`: `kind: Library`, no dependencies, `native: full`):

| File | Lines | Role |
|---|---|---|
| `kinmath.aowl` | 250 | pure arithmetic: axes/directions, `spinDegrees(speed, ticks, offset)` = `(ticks * speed * 0.3 + offset) mod 360`, cog phase offsets (22.5 / 11.25 degrees), Euler for an axis, `turnAbout`, `alignUpTo` |
| `kinvisual.aowl` | 592 | the recipe grammar: one line `block TAB kind TAB key=value;...` says which part of which block spins about which axis at which multiple of the speed (`model`, `axis`, `orient`, `mult`, `offset`, `when`, `reads`, `slide`, `drive`, `show`), parsing and `poseFor` |
| `kindrive.aowl` | 293 | per-machine animation functions (press head, mixer pole, deployer, steam engine) from block-entity numbers (`reads`) |
| `kinreg.aowl` | 57 | the catalog `kinetic.visuals` (`kineticOfferVisuals(provider, lines)`) through which a provider mod hands recipes to the engine half |
| `main.aowl` | 15 | logs a line; no logic |

The ENGINE half is `aoughwl.voxel/vxkinetic.aowl`: it reads the recipes, and for each block entity near the camera gets a `KinCell` through
`kineticFeedData(x, y, z, atY, reference, doc)` (the speed is `kineticSpeedOf(doc)`, the NBT key `Speed`, written by Create's Fabric block entities) or
`kineticFeed(x, y, z, reference, speed)` ("a caller that has no data to read"). It draws each part with `animatePart` every frame from
`cells[c].speed`. So **the only source of speeds is a server that sends Create block entities**: the Fabric path, which the goal removes. With
our server (no block entities for Create, no Create blocks at all) nothing spins.

## 1. Two jobs, kept apart

| Job | Where the truth lives | Today | After the rebuild |
|---|---|---|---|
| **A. Static kinetic blocks** (shafts, cogs, gearboxes, motors, press head) spin in place at a speed | server: `rescan` solves the networks | block entity `Speed` from Fabric | `create:kinetic` payloads (section 3) feed `kineticFeed` |
| **B. Rotating contraptions** (a bearing's platform, later pistons, pulleys) are blocks that MOVE | server: a **kinematic body** (`BodyEntity.kinematic`, pose = `spinBody`) | nothing (a Fabric contraption entity) | the existing body stream (`jester:bodies`) plus `aoughwl.bodies`: no kinetic mod involved |

B needs NO new client work beyond what already exists: the pose arrives as STATE frames with `angvel`; `aoughwl.bodies` (`bodycore.aowl`) interpolates
at `server_tick - 2` (linear + slerp, extrapolation of at most 4 ticks with `vel/angvel`) and draws through `voxel.bodies` (`set` once, `place` per frame);
local collision and carry already exist (`bodycollide.aowl`, `voxel/vxbodyride.aowl`: `bodyRideCarry` adds omega x r, `bodyRideResolve` after `tickMove`).
The server keeps `vel + angVel x (p - com) = angVel x (p - pivot)` true, which is exactly the formula those use. A kinematic body is indistinguishable
from a physics body on the wire, which is the point of building on the body system. Two small items only: (1) the extrapolation with a constant
`angvel` is exact for a bearing, so the 4 tick cap could be lifted for bodies that sent the same `angvel` for 10 frames; (2) a stopped contraption
sends `angvel = 0` without `asleep` (it is not asleep: it is posed by a machine), so STATE frames go on at the keyframe rate only; the server already does that.

## 2. The rebuilt library

Split `aoughwl.kinetic` into three layers so that the speed SOURCE can change without touching the arithmetic or the recipes:

```
aoughwl.kinetic            library (as now): kinmath, kinvisual, kindrive, kinreg   [unchanged files]
  + kinsource.aowl  NEW    the seam: where a cell's speed comes from
  + kinnet.aowl     NEW    decoder of create:kinetic (pure) and its state table
aoughwl.voxel/vxkinetic    unchanged API: kineticFeed / kineticFeedData
```

* `kinsource.aowl` (pure). `type KinSource = enum ksNbt, ksNet`; one function `speedFor(cell)`: if a net entry exists for the position (and is fresh: `lastTick`
  within 40 ticks) use it, else fall back to the block entity `Speed` (the Fabric path, kept until it is removed, then deleted in one commit).
* `kinnet.aowl` (pure, no host calls, tested in a `kinnet_test.aowl` against hand-written byte vectors like `jester_net_test`): `decodeKinetic(bytes) -> seq[Entry]`,
  a table `pos -> (rpm, phase, stamp, netId)` and `netInfo(netId) -> (state, capacity, demand)`.
* The glue lives where the other net consumers live: `aoughwl.bodies/main.aowl` already polls `jester.net` (`sub bodies`, `take ...` every ~30 ms). A new
  `sub kinetic` verb on `jester.net` (voxel's service over `aoughwl.mcnet/netjester`) returns rows like `bodies` does; the mod that owns the
  rendering (the `kinetic` service, NEW, or `aoughwl.bodies` renamed to cover both) forwards entries with `kineticFeed(x, y, z, reference, speed)`, where
  `reference` is the CLIENT'S OWN block state at that position (the client knows its world; the server never sends names). This keeps "no mod ids or name
  heuristics": the recipe table decides from block + state whether and how a block spins.
* Phase continuity (so two meshing cogs never interpenetrate): the client angle must be a function of GAME TIME, like the wind clock
  (`world.clock` game time + TIME_SYNC offset, decided in PROTOCOL.md). The `spinDegrees(speed, ticks, offset)` formula already is; feed it
  `ticks = server game time`. On a speed change the server sends `(tick, rpm, phase)` so the client integrates `phase + 0.3 * rpm * (t - tick)`; without
  `phase` a speed change would jump the angle. The cog offset (22.5 / 11.25) stays client side (it depends on position only).

## 3. Wire format (NEW, draft; not in PROTOCOL.md yet)

Channel `jester:kinetic` (server to client), capability bit `kinetic` (next free bit in section 2.1 of PROTOCOL.md; the server advertises it only when the Create mod is on).
Same conventions as `jester:bodies` (varints, frame limit, `RESYNC_REQ`).

| Type | Content |
|---|---|
| `0x01 SNAPSHOT` | `varint chunkX, chunkZ`, `varint count`, `count x { u8 relX(4) relZ(4), varint y+64, i16 rpm*16, f16/u16 phase degrees*100, varint netId }`. Sent when a chunk enters the viewer's range and on RESYNC. |
| `0x02 DELTA` | `varint server_tick`, `varint count`, entries as above with absolute chunk + position; only nodes whose speed changed. |
| `0x03 NET` | `varint netId, u8 state (0 idle, 1 running, 2 jammed, 3 overstressed), f32 capacity, f32 demand`, short reason text (for a jam: the two cell positions). Sent on change. Drives the goggles-style overlay (section 5). |
| `0x04 BODYPART` | `varint bodyId, varint count`, entries with BODY-LOCAL cell, rpm, phase: kinetic blocks that ride a contraption (section 4). |

Rate: a typical base changes speeds a few times a minute; deltas are rare. A motor starting changes every node of its network at once: the server sends ONE
`0x02` frame (nodes are in `solve` order), split at `max_frame`. Per viewer interest = chunks within the body view distance (128 enter, 144 leave).
Cost estimate: 8 bytes per node; a 2000 node network = 16 KB once.

## 4. Kinetic blocks that ride a contraption (the real rebuild)

A cog on a rotating platform must turn about its own axis AND move with the body. Today `vxkinetic` draws parts in world space from `KinCell.x/y/z`. The change:

1. `KinCell` gets `bodyId` (0 = world) and body-local `lx, ly, lz`.
2. Server: when a contraption is assembled, kinetic blocks inside it are included in the body as ordinary cells (they are blocks), and the server sends
   `0x04 BODYPART` for the ones that are still connected to a network INSIDE the contraption (a bearing's contraption can contain its own gear train). Their
   speed is relative to the body (the contraption's solved sub network), so the same arithmetic applies.
3. `vxkinetic.animatePart` multiplies the part's local transform by the body's pose from `voxel.bodies` (the same matrix `place` uses). This needs a voxel
   change: `voxel.bodies` must expose the current matrix of a body (a verb `pose <id>` returning the 12 numbers) or accept `attach <bodyId> <partId>`; today
   `place` takes origin + Euler angles per frame and only moves block sets. **This is the one piece with no existing hook** and it needs a rebuild of voxel
   (engine half), so it is the last step.
4. The static baked model of a spinning block inside a body must be hidden in the body's block set (`hidesBlock` already exists in `kinvisual`:
   `hidesBlock(all, name)`), otherwise a stationary shaft is drawn under the spinning part. `voxel.bodies set` should skip hidden cells the way the world mesher does.

## 5. UI and feedback (flow kit, no new drawing code)

* An overlay (the "goggles" view) built with `aoughwl.flow.kit`: looking at a kinetic block shows `rpm`, network state and `capacity / demand su`, and for a jam the
  reason from `0x03 NET`. Colour by state (overstressed red, jammed orange). It reads only `kinnet`'s table.
* Server side the same numbers are available by `/create speed` and `/create scan` today (they are the reference for the first client check).

## 6. Order of work, with what each step needs

| Step | Change | Needs | Verification |
|---|---|---|---|
| 1 | `kinnet.aowl` + `kinnet_test.aowl` (decoder, table, phase integration) | nothing | byte-vector unit test, no game |
| 2 | `kinsource.aowl` seam, voxel feeds through it; NBT path unchanged | rebuild `aoughwl.kinetic` and `aoughwl.voxel` | existing kinetic tests, then a Fabric world still spins (regression) |
| 3 | `jester:kinetic` in `netjester` (`sub kinetic`, decoder), `kinetic` capability | server channel (CREATE_PORT item 3) | `jester_net_test` extended with 0x01/0x02/0x03 vectors; live: `/create motor` then watch a stand-in shaft with a kinetic recipe turn |
| 4 | server `0x04` + `KinCell.bodyId` + `voxel.bodies pose` + hidden cells | voxel rebuild | a gear train on a rotating platform, eyeball |
| 5 | goggles overlay | step 3 | `/create` numbers equal the overlay's |
| 6 | delete the Fabric NBT path | Fabric removal (phase 3 item 4) | none |

Constraint for every step: **never build while the game runs**; rebuild all dependent mods after an export change (see the project's mod rebuild notes);
a step is done only with a unit test that fails if the change is wrong and one line from an in-game launch.

## 7. What is deliberately NOT moved

* `kinmath`/`kinvisual`/`kindrive`: pure and generic; they already know no mod. Keep.
* The solver stays on the server. The client never runs `src/mods/create/kinetic.aowl`: it is authoritative there, and a client that predicted speeds would
  disagree at every jam. The module IS pure and shareable (phase 1 item 2) should an offline "preview" mode ever want it (a schematic ghost showing how a
  planned gear train would turn).
* Collision, carry and body interpolation: already done in `aoughwl.bodies`/`voxel`; nothing in the kinetic mod should duplicate them.
