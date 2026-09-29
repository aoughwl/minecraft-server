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

- `gen_attributes.nim` → `Attribute` object type + 40 named constants (from `attributes.json`, a name->{id,default_value} map, sorted by id per upstream's explicit `sort_by_key`) plus `allAttributes()`. Note: a `const seq[Attribute]` literal referencing other consts isn't foldable at compile time in Nimony ("cannot evaluate expression at compile time") - changed to a plain `proc allAttributes*(): seq[Attribute]` instead. **This unblocks `effect.rs`/`potion.rs`, previously skipped for needing this exact file** (they also need `data_component_impl::Operation`, still unported - not fully unblocked yet, but one of their two blockers is now cleared).
- `gen_painting_variant.nim` → `PaintingVariant` (51 variants, directory shape like the cat_variant/wolf_variant family, plus a *second* input - a `tags/painting_variant/placeable.json` tag file listing which variants are placeable in survival, cross-referenced by asset id/stem to set each variant's `isPlaceable`). First generator combining two independent JSON sources. Used `path(...)` (lowercase, the `std/paths` constructor proc) rather than `Path(...)` (a type-conversion call syntax that doesn't work the same way in Nimony) - noted here since every other generator using `listJsonStems` already got this right but it's easy to typo.

- `gen_game_rules.nim` → `GameRule` enum (59 variants) + `GameRuleKind` (bool/int) + per-rule default value accessors, from `game_rules.json`'s name -> (bool | int | {"default": int, ...}) map. Scope note: upstream's generator also emits a full `GameRuleRegistry` struct with serde (de)serialization and mutable `get`/`get_mut` accessors - that's a runtime storage/registry design, not pure data, deferred to whenever game rules get wired into an actual world/server type; this generator ports the data half only (the enum, kind, and defaults). **Found and fixed a new, more insidious Nimony compiler bug here** (minimally reproduced, documented in the file itself): `seq[T].sort(closureComparator)` crashes at C-codegen - not at `nimony check`, which passes clean - when `T` is a plain object with an enum-typed field; the same pattern works fine sorting tuples elsewhere in this port. Worked around with a closure-free manual insertion sort (`manualSortByName`) rather than `algorithm.sort`. This is worth any future generator author knowing before trusting `nimony check` alone on a `.sort()`-using file - `nimony c -r` it too.

- `gen_slot_ranges.nim` → `slotRanges()`/`slotRangeAllNames()`/`slotRangeSingleSlotNames()`/`getSlotRange(name)` (165 entries, from `slot_ranges.json`, a flat `name -> seq[int]` map). Unlike every other generator so far, upstream doesn't build an enum here - it matches on the literal string keys directly (`get_slot_range(name: &str)`), so this does the same rather than inventing one. Added `readStringIntSeqMapSorted` to `codegenutil.nim` for the `BTreeMap<String, Box<[usize]>>` shape.
- `gen_damage_type.nim` → `DamageType` object + 51 named constants (directory shape, `assets/datapack/data/minecraft/damage_type/*.json`) + `damageTypeFromName`/`damageTypeFromId`. Three small nested enums (`DeathMessageType`, `DamageEffects` - optional, absent -> `hasEffects: false` - and `DamageScaling`). Upstream's `Taggable` impl (registry-tag lookup via `tag.rs`'s `RegistryKey`) is skipped, needs that unported module.
- `javaversion.nim` (in `src/util/`, not `src/data_codegen/` - see below) - direct port of `version.rs`'s `JavaMinecraftVersion` enum + `to_field_ident`. Not JSON-driven (it's a hand-authored, ordered version list mirrored from `pumpkin_util::version` for codegen's own token-emission use), so it's a plain hand-port rather than a `gen_*.nim` script; belongs alongside the rest of `pumpkin-util` in `src/util/`. Declaration order preserved exactly (upstream derives `Ord` from it for version comparisons).

That's 34/90 submodules done (33 in `src/data_codegen/`/`src/generated/` + 1 direct util port).

- `gen_registry.nim` → `src/generated/registry_data.nim` (**`registry.rs`, 234
  lines, now done** - previously flagged as "investigated but deferred").
  Ported `jsontonbt.nim` (`jsonToNbtTag`, a generic recursive `JsonNode ->
  NbtTag` converter mirroring `registry.rs`'s local `json_to_nbt_tag`
  closure exactly, 6-way match on JSON value kind) as a standalone reusable
  module, then the generator itself: walks all 32 `SYNCED_REGISTRIES`
  directories (the constant array has 32 entries, not ~31 as originally
  estimated - includes both `worldgen/biome` and
  `worldgen/block_state_provider`) under
  `../upstream-ref/assets/datapack/data/minecraft/`, reads every entry's
  JSON via `listJsonStems`, converts to NBT, and serializes each as an
  unnamed compound via the existing `src/nbt/nbtdoc.nim` `writeUnnamed`
  (Java mode) - reusing the complete NBT writer rather than reimplementing
  serialization. Also reproduces upstream's one hardcoded special case: a
  synthetic `"raw"` `chat_type` entry injected for vanilla parity (not
  present in any `assets/` JSON file), built from an inline JSON literal via
  `parseJson`. Byte output is emitted as `@[1'u8, 2'u8, ...]` seq literals
  (Nimony has no raw byte-string literal syntax like Rust's `b"..."`).
  **Run and verified**: `nimony c -r src/data_codegen/gen_registry.nim`
  actually walked the real 32 directories and wrote
  `src/generated/registry_data.nim` (511 lines, 32 registries, 433 JSON
  entries + 1 synthetic `raw` = 434 total), which itself `nimony check`s
  clean. Spot-checked by hand-decoding the `chat_type/chat` entry's NBT
  bytes against its source JSON (`{"chat": {"parameters": ["sender",
  "content"], "translation_key": "chat.type.text"}, "narration": {...}}`) -
  the byte stream matches exactly (compound tag id, nested "chat" compound,
  "parameters" string-list of length 2 containing "sender"/"content", etc.).

Skipped after investigation (documented here, not silently dropped):
`potion.rs` (needs `effect.rs`'s `StatusEffect` - `effect.rs` itself is now
only blocked on `data_component_impl::Operation`, not `attributes` anymore
since `gen_attributes.nim` landed) - revisit once `data_component_impl` lands.

- `gen_dimension.nim` → `src/generated/dimension.nim` (`Dimension` object +
  4 named constants: `OVERWORLD`/`OVERWORLD_CAVES`/`THE_END`/`THE_NETHER`,
  from `assets/datapack/data/minecraft/dimension_type/*.json`). Scoped to
  the core world-shape fields (skylight/ceiling, Y bounds, coordinate
  scale, infiniburn/timelines tags, fixed-time) - deliberately does NOT
  port upstream's `attributes` sub-object (visual/audio/gameplay cosmetics:
  sky/fog/cloud color, ambient sound/music tracks, bed-sleep rules; ~15
  optional nested JSON paths with hex-color parsing), which is
  client-rendering data, not core world logic; documented as deferred in
  the generator's own doc comment. `monster_spawn_light_level` (an
  `IntProvider`, upstream's `value_to_int_provider` helper is itself
  unported) is captured as a small structured string (`"const:<n>"` or
  `"<type>:<min>..<max>"`) rather than dropped or fully modeled.
  **Run and verified**: `nimony c -r src/data_codegen/gen_dimension.nim`
  wrote all 4 real dimensions; output `nimony check`-clean; spot-checked
  every field against the source JSON (`overworld.json`'s
  `min_y:-64`/`height:384`/`ambient_light:0.0`/`coordinate_scale:1.0`
  /`has_skylight:true`/`has_ceiling:false` all match, and the
  `fixed_time`-absent vs. `has_fixed_time:true`-with-no-`fixed_time`
  distinction between `overworld.json` and `the_end.json`/`the_nether.json`
  is preserved correctly).
  **Caught a real bug in its own first pass**: `{.noinit.}` (needed to
  satisfy Nimony's "cannot prove initialized" check on the loop-filled
  return object) skips zero-initialization entirely, so a field only set
  on *some* branches of the parsing loop (here, `fixedTime`, only written
  when the JSON actually has a non-null `"fixed_time"` key) held
  uninitialized memory garbage rather than 0 for entries lacking that key
  - `overworld.json`'s generated constant briefly showed
  `fixedTime: 718871328032`. Fixed by explicitly assigning
  `result = DimEntry()` before the loop even under `{.noinit.}`. Worth any
  future generator (or any Nimony code) using `{.noinit.}` on a
  partially-conditionally-filled object knowing this explicitly, not just
  trusting `nimony check` passing.
  **Also hit and worked around**, not deeply investigated: `for (a, b) in
  someLocalSeqVar:` (tuple-destructuring a `for` loop's iteration variable
  over a `let`-bound local `seq[(T,U)]`) crashed the compiler with an
  internal `[Bug]` parser assertion ("expected ')', but got: (let
  stem...)"), even though the exact same syntax over a direct call
  expression (`for (stem, path) in listJsonStems(dir):`) works fine
  elsewhere in this same directory. Worked around with indexed access
  (`stems[i][0]`/`stems[i][1]`) instead of destructuring. Also noted:
  `writeFile` resolved to a wrong/ambiguous overload (`Path`-taking
  instead of the plain `string`-taking one) when both `std/paths` and this
  file's own `codegenutil` import were in scope together with an explicit
  `path(...)`-wrapped argument - reverting to a bare string-literal
  argument (no explicit `path(...)` wrap) resolved correctly. Neither
  filed externally (SendFeedback quota exhausted this session) - flagged
  here for whoever next hits either.

- `chunk_view_lut.rs` → `src/generated/chunk_view_lut.nim` (**no JSON input at
  all** - pure math: concentric view-distance and Chebyshev/square ring
  offset tables). Upstream computes this inside a `proc_macro2`/`quote!`
  build script to bake `static` zero-cost arrays; Nimony has no build-time
  codegen macro to reproduce that trick and there's no external data file
  for a generator to read, so this is ported directly as a module that
  builds its tables once at load time (`let chunkViewLut* = build...()`)
  rather than emitting a giant array-literal source file (the Chebyshev
  table alone has 9409 entries at the max radius - a literal would work,
  per `gen_sound.nim`'s 1991-variant precedent, but a computed proc is
  simpler and behaviorally identical). **Verified**:
  `chunk_view_luttest.nim` checks the dist<2-empty rule, the
  relX²+relZ²<d² filter for every offset at several distances, the ring
  size = 8r / square size = 1+4r(r+1) closed-form identities, and the
  total-offset-count sum formula - all pass (`nimony c -r`, 9409 total
  Chebyshev offsets confirmed).
- `context_provider.rs` → `src/data_codegen/gen_context_provider.nim` →
  `src/generated/context_provider.nim`. Walks
  `assets/datapack/data/minecraft/context_{int,float}_provider/` (one level
  of category subdirectory, e.g. `cooking/time_coal.json`) and embeds each
  JSON file's raw text (upstream does this via `include_str!` at Rust
  compile time) into a `case`-based lookup proc keyed by both the bare id
  and the `minecraft:`-namespaced id, plus a name-list proc, for both int
  and float provider kinds. **Run and verified**:
  `nimony c -r src/data_codegen/gen_context_provider.nim` walked the real
  26 int + 4 float provider files and wrote a 78-line
  `src/generated/context_provider.nim` that itself `nimony check`s clean;
  spot-checked `cooking/time_coal`'s embedded JSON byte-for-byte against
  its source file (`"left": 1600` and the full nested `conditional`
  structure match exactly).
  **Found and worked around a new Nimony compiler bug**: calling two
  different `{.raises.}` procs (a `walkDir` iterator and `readFile`)
  within the same `try` block - even indirectly, walkDir's loop body
  calling `readFile` - produces broken C codegen (`request for member
  'fld_0' in something not a structure or union`, an `ErrorCode`/tuple
  type confusion in the generated C), while `nimony check` passes clean.
  Fixed by splitting into two passes: one `try` block collects file paths
  via `walkDir`, a second, separate `try`-wrapped proc (`readOne`) reads
  each file's contents afterward - no `{.raises.}` call nests inside
  another `{.raises.}` call's `try` scope. Documented here since
  SendFeedback quota was exhausted this session; worth filing upstream
  once quota resets.
- `test_instance.rs` (155 lines) - investigated, not ported this pass.
  Recursively scans `test_instance/` directories across multiple
  "packs" (the base `assets/datapack` plus every subdirectory of
  `assets/tests/datapacks`), each pack scanned per-namespace with
  unbounded-depth directory recursion - a genuinely bigger task than
  `chunk_view_lut`/`context_provider`'s one-level scans, deferred to a
  dedicated pass rather than rushed.
- `noise_parameter.rs` → `gen_noise_parameter.nim` →
  `src/generated/noise_parameter.nim`. Walks the real (flat, no
  subdirectories) `assets/datapack/data/minecraft/worldgen/noise/`
  directory (62 files), applies upstream's `first_octave`/`base_octave`
  and `amplitudes`/`amplitude_modifiers`/`octave_count` fallback chains,
  and precomputes each entry's MD5-derived `lo`/`hi` (upstream hashes
  `"minecraft:<name>"` and reads the first/second 8 bytes as big-endian
  u64s). **Found and worked around a real Nimony `std/json` bug**: the
  `{}` object-lookup operator returns a default-constructed `JsonNode()`
  on a missing key, and calling `.kind` (or nearly anything else) on that
  default value crashes at runtime with an internal assertion failure -
  `nimony check` passes clean, only `nimony c -r` catches it. Reproduced
  standalone (`var n = JsonNode(); discard n.kind` alone crashes). Fixed
  by adding `jsonTryGet(tree, key): (bool, JsonNode)` to
  `codegenutil.nim`, which walks `pairs()` itself and never touches the
  broken default - now the house way to look up an optional JSON key
  across this whole codegen suite, not just this file. Documented here
  since SendFeedback quota was exhausted this session; worth filing
  upstream once quota resets. **Verified**: `noise_parametertest.nim`
  (`nimony c -r`) checks the entry count (62), `aquifer_barrier`'s
  fields including its `lo`/`hi` cross-checked byte-for-byte against
  Python's `hashlib.md5` (`16244762748638791999`/`1391399305011792652`,
  exact match), `temperature`'s `amplitude_modifiers` fallback path, and
  a missing-key lookup correctly returning not-found.

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
