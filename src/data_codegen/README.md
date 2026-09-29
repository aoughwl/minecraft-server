# data codegen port

`crates/data` in the upstream repo is ~1.5M lines, but the project
README's porting strategy already calls this correctly: it's almost entirely
*generated* Rust source (block/item/biome/sound/etc. registry tables), not
hand-written logic. `tools/codegen` (36.8k lines across ~90 small
generator submodules, one per data domain, driven by `main.rs`) is the actual
generator — it should be ported instead of the generated output.

## What codegen does

Each submodule (`sound_category.rs`, `dye_color.rs`, `block.rs`, `item.rs`,
`biome.rs`, `recipes.rs`, ... ~90 of them, listed in `main.rs`'s `mod`
declarations) does the same three-step thing:

1. Read one or more JSON files from `assets/` (checked into the repo root,
   **confirmed present**: `assets/` is 92MB of Minecraft data-generator JSON
   output — `blocks.json`, `items.json`, `sound_category.json`, `biome.json`,
   etc. — this is not a blocker; the inputs already exist).
2. Build a `proc_macro2::TokenStream` via `quote!{...}` — literal Rust AST
   nodes, assembled programmatically (string formatting, `format_ident!`,
   `heck::ToPascalCase` for name conversion).
3. `main.rs` collects every submodule's `TokenStream`, pretty-prints it
   (via `prettyplease` or similar) and writes `.rs` files into
   `crates/data/src/generated/`.

## Why this isn't a mechanical port

Step 2 is the only real obstacle, and it isn't a missing-primitive problem
the way gzip/elliptic-curve-crypto/HTTP were for other crates — it's a
*better-off-different* situation. Rust needs `quote!`/`proc_macro2` because
it's building a real `TokenStream` (structured Rust AST) that then gets
pretty-printed. Nimony has no equivalent macro-token-stream API for
emitting *its own* source **and doesn't need one**: a Nimony generator can
just build the output as a plain string and `writeFile` it directly. That's
strictly simpler than what Rust is doing here, not a gap.

Nimony's stdlib does have `std/json` (`~/nimony/lib/std/json.nim` +
`parsejson.nim`) — confirmed present, unlike the gzip/crypto/HTTP gaps found
elsewhere in this port. Its API is a bit different from classic Nim's `json`
module (a `JsonTree`/`JsonNode` cursor pair rather than a `JsonNode` DOM with
`%*` sugar — see `parseFile`, `root(tree)`, `.items`, `.getStr()` in the
proof-of-concept below), but everything needed is there.

## What's done here

`gen_sound_category.nim` is a complete, working, **run-and-verified** port
of the smallest submodule (`sound_category.rs`, 59 lines) establishing the
pattern:

```
JSON (assets/sound_category.json, from ../upstream-ref, upstream's own repo)
  -> parseFile/root/items/getStr (std/json)
  -> plain string-building (toPascalCase port of heck::ToPascalCase,
     manual case/enum text assembly)
  -> writeFile -> src/generated/sound_category.nim
```

Run it with:
```
nimony c -r src/data_codegen/gen_sound_category.nim
```//
It reads the real `../upstream-ref/assets/sound_category.json` and wrote a
type-checked, correct `src/generated/sound_category.nim` (verified: the
enum values, `fromName`, and `toName` case bodies match the 11 real sound
categories in the JSON exactly, and `nimony check` passes on the output).

`codegenutil.nim` factors the reusable pieces (`toPascalCase`,
`readStringArray` for `Vec<String>`-shaped inputs, `readStringIntMapSorted`
for `BTreeMap<String, uN>`-shaped inputs, sorted the same way a `BTreeMap`
iterates) out of that proof-of-concept so later generators don't each
reimplement them. Five more submodules now use it, all run-and-verified
the same way (`nimony c -r src/data_codegen/gen_<name>.nim`, output
`nimony check`-ed, values spot-checked against the source JSON):

- `gen_entity_pose.nim` → `EntityPose` (18 variants, from `entity_pose.json`)
- `gen_screen.nim` → `WindowType` (from `screens.json`)
- `gen_scoreboard_slot.nim` → `ScoreboardDisplaySlot` (from `scoreboard_display_slot.json`)
- `gen_entity_status.nim` → `EntityStatus` with explicit discriminants (64 variants, from `entity_statuses.json`, a name->u8 map)
- `gen_world_event.nim` → `WorldEvent` with explicit discriminants (from `world_event.json`, a name->u16 map)

- `gen_chunk_status.nim` → `ChunkStatus` (10 variants, from `chunk_status.json`, a flat string array), plus `chunkStatusToWireName` standing in for upstream's `#[serde(rename = "minecraft:<status>")]`
- `gen_flower_pot_transformations.nim` → `getPottedItem(itemId: uint16): uint16` (from `flower_pot_transformations.json`, an item-id->potted-block-id map), returning the raw block id since the `BlockId` wrapper type doesn't exist yet
- `gen_game_event.nim` → `GameEvent` (61 variants, from `game_event.json`, a flat string array)
- `gen_map_color.nim` → `MapColor` object + named constants (64 entries, from `map_colors.json`, an array of `{id,name,col,hex,rgb}` objects) - added `readMapColors`/`toShoutySnakeCase` to `codegenutil.nim`; also the first generator needing object-array (not flat-array or string-map) JSON, which surfaced that Nimony's `std/json` `JsonNode` has no `[]` field-index operator - object field lookup means scanning `pairs()` for the matching key, documented in `readMapColors`'s doc comment
- `gen_statistic.nim` → `StatisticCategory` (9 variants, explicit `i32` discriminants) + `CustomStatistic` (156 variants) from `stats.json`'s nested `{category: {id, entries: {stat: {id}}}}` shape - read directly via `JsonNode.pairs()` rather than a `codegenutil` helper since the nesting is one-off; JSON object key order is preserved by `pairs()` (matches upstream's `IndexMap` insertion-order semantics, unlike the `BTreeMap`-sorted helpers used elsewhere)
- `gen_message_type.nim` → `chat_type` constants (`u8`, from a *directory* of one-field JSON files under `assets/datapack/data/minecraft/chat_type/`, numbered by sorted filename order, plus a synthetic trailing `RAW`) - first generator to read a directory instead of a single JSON document
- `gen_meta_data_type.nim` → `MetaDataType` (from `meta_data_type.json`'s flat name->i32 map, with a name-canonicalization/alias step: some data-type names have synonyms across Minecraft versions and must collapse to one id, then get restated as alias constants)
- `gen_particle.nim` → `Particle` (128 variants, from `particles.json`, a flat string array) plus index-based `fromId`/`toId` (enum declaration order = wire id order)
- `gen_decorated_pot_pattern.nim`, `gen_cat_variant.nim`, `gen_banner_pattern.nim` → same directory-of-JSON-files shape as `message_type`, but keyed by stem with per-entry string fields (`asset_id`, sometimes `translation_key`) rather than positional. This pattern (walk a directory, parse each file's small JSON object, sort by stem, emit an enum + accessor procs + an `all()`-equivalent array) recurs across several more submodules (frog_variant, wolf_variant, chat_type, trim_material, trim_pattern, painting_variant, and others) - `codegenutil.nim` now has `listJsonStems`/`jsonStringField`/`stemOf`/`lastIndexOf` factored out for it, so those should be quick following this template.
- Skipped: `gen_spawn_egg.nim` - needs the still-unported `entity_type` generated enum (cross-references `EntityType` variants by name, which don't exist as Nimony code yet); revisit once entity_type.rs is ported.

- `gen_chat_type.nim` → `ChatType` (7 variants, directory shape, with one nested field - `chat.translation_key` - handled by an inline pairs()-scan since it's one level deeper than `jsonStringField` reaches)
- `gen_frog_variant.nim` → `FrogVariant` (3 variants) - notable upstream quirk preserved faithfully: the enum itself is hand-hardcoded to `Cold/Temperate(default)/Warm` rather than generated from the directory scan (which is only used for the name/texture accessor tables), and `from_id` falls back to `Temperate` for unrecognized ids rather than `None` like every other generator's `fromName` does
- `gen_wolf_variant.nim` → `WolfVariant` (9 variants, from `wolf_variant/*.json`, a nested `assets.{angry,tame,wild}` object per entry) - added `jsonNestedStringField` to `codegenutil.nim` for one-level-deep field access; upstream's `baby_assets`/`spawn_conditions` fields are parsed but never actually used in its emitted output, so skipped here too (matches real output, not the struct shape)
- `gen_trim_material.nim` → `TrimMaterial` (11 variants, from `trim_material/*.json`: `palette_id` top-level + nested `description.{color,translate}`, both optional, default `""`)
- `gen_trim_pattern.nim` → `TrimPattern` (18 variants, from `trim_pattern/*.json`: `asset_id`/`decal` (bool, default false) top-level + nested `description.translate`) - added `jsonBoolField` to `codegenutil.nim`

- `gen_map_decoration.nim` → `MapDecorationType` (40 entries, from a single positional JSON array `map_decorations.json`, id = array index) - first generator to read a flat positional array of mixed-type objects rather than a name-keyed directory/map; `map_color` defaults to -1, `exploration_map_element` defaults to false when absent

- `gen_dye_color.nim` → `DyeColor` (16 variants, from `dye_colors.json`, a flat positional array with 7 fields per entry) - `byId`/`byName` fall back to Black on miss, matching upstream's `#[default]`/`unwrap_or_default()` behavior
- `gen_jukebox_song.nim` → `JukeboxSong` (22 variants, directory shape, id = declaration order) - added `jsonFloatField`/`jsonIntField`/`isAsciiDigit` to `codegenutil.nim`; variant names starting with a digit (`11`, `13`, `5`) get an `Id` prefix like upstream's `format_ident!("Id{}", ...)` does
- `gen_sound.nim` → `Sound` (1991 variants, from `sounds.json`, a flat string array; id = declaration order matching upstream's `#[repr(u16)]`) - names contain dots (`"entity.allay.ambient_with_item"`), which required extending `toPascalCase` to split on `.` as well as `_`/`-`/space (heck's `ToPascalCase` already treats any non-alphanumeric as a word boundary, so this brings the port in line rather than diverging); `nimony check` takes ~14s on this file, the slowest generated output so far
- `gen_instrument.nim` → `Instrument` (8 variants, directory shape) - first generator with a cross-reference to another *generated* module (`import sound` for the `sound()` accessor), verified the import resolves and type-checks correctly once both files sit side by side in `src/generated/`

That's 27/90 submodules done.

Skipped after investigation (documented here, not silently dropped): `effect.rs`
(needs unported `attributes::Attributes` and `data_component_impl::Operation`)
and `potion.rs` (needs `effect.rs`'s `StatusEffect`, transitively blocked the
same way) - revisit once `attributes`/`data_component_impl` land.

## What's NOT done

The other ~71 submodules up through `block.rs`, `item.rs`, `biome.rs`, `recipes.rs`,
`noise_router.rs`, `noise_settings.rs` (these last few are large and encode
real structural complexity - nested data shapes, cross-references between
registries, not just flat string arrays). Each needs the same treatment as
`sound_category.rs`: read its `.rs` source, understand its JSON input shape
and what Rust type/impl it emits, then hand-write the equivalent
string-building Nimony generator. This is real, substantial work - the
90-file breadth is the actual cost, not any per-file blocker - budget
accordingly; a reasonable next step is forking out several of these in
parallel the way other crates in this port were, since each submodule is
independent of the others (they don't call into each other, `main.rs` just
collects and writes each one's output separately).

Two things worth deciding before going further, not blockers but design
choices:
- **Output layout**: this PoC writes flat files under `src/generated/`.
  Once there are ~90 of them (mirroring `crates/data/src/generated/`
  upstream), consider whether they should be organized into subdirectories
  matching upstream's, and whether a single `main.nim` driver (mirroring
  `tools/codegen/src/main.rs`) should replace running each
  generator file individually.
- **`main.rs`'s non-generator responsibilities**: skimmed but not yet
  analyzed - it may also emit non-Rust-source side outputs (the `wit/`
  submodule directory suggests some submodules generate WIT interface
  definitions for the plugin system, not Rust source at all; those may or
  may not be in scope depending on what src/plugin_runtime/'s WASM-hosting
  gap (see its own README) resolves to).
