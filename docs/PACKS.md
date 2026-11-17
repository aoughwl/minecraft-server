# Content packs

A content pack is a folder (or a `.zip`) with a `pack.json` and a few JSON data files. It changes data the server already
has: material properties, climate and wind parameters, and simple chat commands. No code runs; a bad pack can only be
refused, never crash the server. Source: `src/physics/packs.aowl` (loader, pure), `src/plugin/packscmd.aowl` (commands).
Tests: `src/physics/packstest.aowl`. Worked example: `examples/packs/example_pack/`.

## Where packs live

`packs/` next to the server (the working directory). Each pack is either

- a folder `packs/<anything>/` containing `pack.json`, or
- a file `packs/<anything>.zip` with `pack.json` at the zip root (stored or deflated entries, CRC-32 checked, 4 MB per file).

Packs load at start-up (when `packs/` exists) and on `/packs reload`.

## pack.json

```json
{ "format": 1, "id": "my_pack", "name": "My pack", "version": "1.0.0",
  "description": "what it does", "priority": 0, "depends": ["other_pack"] }
```

`format` (must be 1) and `id` (`a-z 0-9 _`, 1..40 characters, unique) are required. Packs apply in `(priority, id)` order and
a later pack wins a conflict field by field. A pack whose `depends` are not all active is skipped with an error.

## materials.json

Exactly the override document of `src/physics/materials.aowl`:

```json
{ "tags":   { "minecraft:logs": { "density": 700, "stiffness": 12 } },
  "blocks": { "minecraft:stone": { "density": 300 }, "mymod:foam": { "density": 30 } } }
```

Fields (all optional): `density` (kg/m3, above 0), `stiffness` (GPa), `damping` (0..1), `tensile`, `compressive` (MPa),
`dragArea` (faces), `breakThreshold` (kJ), `flammability`, `ignitability` (0..1). A block entry beats a tag entry; names without
a namespace mean `minecraft:`. Unknown fields, negative or out-of-range numbers make the pack invalid. Unknown blocks or tags
are warnings (the block may come from a mod that is not installed). Everything that reads the table (`materialOf`, the structural
solver adapter, fire, blasts, bodies) sees the change at once.

## climate.json

```json
{ "yearDays": 16,
  "field": { "useShelter": true, "useDrafts": true, "shelterSteps": 8, "shelterStep": 2.0, "shelterRise": 6.0,
             "shelterMax": 0.7, "draftRange": 12, "draftSpeed": 2.0 },
  "wind":  { "baseSpeed": 6.5, "baseYaw": 0.0, "turbulence": 0.7, "spatialScale": 48, "temporalScale": 200,
             "altitudeGain": 0.15, "weatherGain": 0.6, "shelter": true, "caveDraft": false, "draft": 0.0 } }
```

`yearDays` (1..3650) sets the season clock (`climate.aowl`), `field` the server's wind-field knobs (`windfield.aowl`),
`wind` the parameters sent to Jester clients in `jester:wind` (clients get an UPDATE within a second). Keys not set keep the
defaults; unknown keys are errors.

## commands.json

```json
{ "commands": [ { "name": "rules", "description": "Show the rules", "level": 0,
                  "reply": ["Line one", "You typed: {args}"] } ] }
```

`/name [text]` replies with the lines to the sender; `{args}` is the text after the command. `level` is the permission level
(0 everyone .. 4). Names are 1..32 characters of `a-z 0-9 _ -` and cannot be a built-in (`packs`, `script`, `op`, ...).

## recipes.json

Validated (`{"recipes":[{"id","type","result",...}]}`) and listed, but NOT applied: the server has no recipe registry yet.
`/packs reload` reports it as not applied.

## enabled.json (per-world enable list)

`packs/enabled.json` is optional:

```json
{ "default": ["example_pack"], "worlds": { "creative": ["example_pack", "other"], "plain": [] } }
```

The world is the save folder's name. A list is an array of pack ids or `"all"`. A world entry beats `default`; without the file
every valid pack is enabled. The material, climate and wind tables are process-wide, so they follow the one world this server
runs (the save folder).

## Commands

- `/packs list` - every pack found with its state (`active`, `disabled`, `INVALID`).
- `/packs info <id>` - metadata, what it provides, its commands, errors and warnings.
- `/packs reload` - re-read everything and re-apply; prints counts, errors (`ERROR pack <id> (<folder>): file.json.path ...`),
  warnings and restart-only notes. Needs permission level 4.

## What reloads live, what needs a restart

Live: material overrides, `yearDays`, field knobs, wind parameters, command reply text, new commands, enable lists.
Restart-only (reported as `RESTART ...`): removing a command (it stays registered and says it is disabled), changing a
command's permission level, recipes. Reload replaces the whole override layer: material overrides set directly by plugins with
`setBlockOverride` are dropped by a reload and must be set again.

## Errors

A pack with any error is skipped whole (never partly applied) and the others still load. Messages name the pack, the file and
the JSON path, for example `ERROR pack p_neg (p_neg): materials.json: blocks.stone: field damping must be between 0 and 1`.
