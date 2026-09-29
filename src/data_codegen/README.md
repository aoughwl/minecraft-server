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

That's 6/90 submodules done.

## What's NOT done

The other ~84 submodules, ranging from `chunk_status.rs`/`flower_pot_transformations.rs`
(similar simple flat-array/map shapes, next easiest) up through `block.rs`, `item.rs`, `biome.rs`, `recipes.rs`,
trivial) up through `block.rs`, `item.rs`, `biome.rs`, `recipes.rs`,
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
