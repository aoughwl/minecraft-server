# Dynamic registries: design note

Status: **design**. Nothing here is implemented yet except where it says so. It answers one question: how does a server mod add a block (or an
item, an entity type, ...) that a vanilla server could not, and how does a Jester client learn about it?

## 1. What exists today

* **Static tables.** Blocks, block states, items, entity types and the synced registries come from generated code
  (`src/generated/block_properties.aowl`: `STATE_COUNT = 32366`, `BLOCK_COUNT = 1196`, ids are `uint16`; `src/generated/registry.aowl`:
  `getSynced(version)`). `Block.fromStateId`, `Block.fromName` and friends read those tables. Nothing can be added at run time.
* **Registry sync** happens once, in the configuration phase (`handleKnownPacks` in `src/server/net/java/config.aowl` sends one
  `CRegistryData` per synced registry, then tags). It carries the registries a vanilla client needs (dimension type, biomes, damage types,
  ...). It does not carry blocks or items: a vanilla client has those numbered by its own game version and the server never sends the numbering.
* **Chunk storage** stores global block state ids (`uint16`) in section palettes, so ids from `STATE_COUNT` up to 65535 fit without a format
  change (about 33 000 spare ids).
* **Client side**, `aoughwl.modded` (`apps/mc/basemods/aoughwl.modded/moddedreg.aowl`) already defines the *tables a client reads*: text lines per table,
  `modded.blockstates` = `name TAB firstStateId TAB stateCount TAB props`, `modded.items` = `rawId TAB name`, `modded.entitytypes`,
  `modded.blockentitytypes`, `modded.menutypes`, `modded.components`, `modded.metatypes`, `modded.payloads`, `modded.fluids`, `modded.sources`.
  Rows are only ever added and the last row for an id wins; raw ids are "the server's", with a `version` row naming the server build they are for.
  A provider fills them with `moddedOfferLines(table, lines)`; the mesher and the item renderer read them. Today the provider is `aoughwl.create`, from static data.

So the client half of "how does it learn about a new block" is a table format that exists; what is missing is the server producing those rows from what
mods registered, sending them, and the server treating ids beyond the static range as real.

## 2. Goals and non-goals

Goals: a server mod registers blocks (with states and properties), items, entity types and block entity types at start-up; ids are stable per world;
Jester clients that granted `modsync` get the rows before play; other clients keep working (a custom block degrades to a vanilla stand-in).

Non-goals for the first version: registering new *registry types*, custom dimensions or biomes, data components beyond a name and schema row,
custom fluids, anything that needs the chunk/lighting code to know a block's shape (shape and light come from the stand-in, section 5).

## 3. The registry model (server)

One module, `src/server/registry/dynamic.aowl` (new), owns a list of **namespaces** (a mod id) and per namespace the rows it registered:

```
DynBlock    { id: "ns:name", props: [name -> values], stand_in: vanilla state, hardness/resistance/light/tool tags (data, not code) }
DynItem     { id: "ns:name", stack_size, block: "ns:name" or "" }
DynEntity   { id: "ns:name", ... }   (later)
```

Registration is a start-up call (`registerBlock`, `registerItem`) made by a server mod before the first player can join. After the server starts accepting
logins the registries are frozen; late registration is an error. That keeps ids stable for the life of a process.

**Ids.** A custom block gets a block id above `BLOCK_COUNT` and a contiguous run of state ids above `STATE_COUNT` (the same shape the client's
`modded.blockstates` expects: `firstStateId`, `stateCount`, properties with the last varying fastest). Items get raw ids above the static item count.

**Stable per-world id map.** The assignment is persisted in the world folder (`jester-registry.json`: `{ "version": 1, "blocks": [ { "id": "ns:name", "first": 32366, "count": 4 } ], "items": [...] }`).
On start-up the server loads it, keeps every id it already handed out, gives new registrations the next free range, and never reuses the range of a mod
that is no longer installed (the blocks in saved chunks stay valid ids; they read back as their stand-in until the mod returns). Chunk data therefore
never needs a migration.

## 4. Telling the client

A Jester client that granted `modsync` receives the registry rows in the configuration phase, before `finish_configuration`:

```
channel jester:registry   (S->C, config)  [new, to be added to PROTOCOL.md]
  u8 type = 0x01 TABLE
  string table        "modded.blockstates" | "modded.items" | ...
  varint count
  count x string line      the table's text line, exactly the client's row format
  u8 more             1 when the table continues in the next message
```

The client calls `moddedOfferLines(table, lines)`, then the existing consumers (mesher, item renderer) see the rows. A `version` row (the server's
protocol/game version) comes first so the client can refuse numbers from a build it does not match. Messages are split at `max_frame` like the manifest.
The set of rows is also hashed (SHA-256 of the canonical text) and put in the `jester:welcome` flags region later so a client can cache by hash; not in the first version.

A client without `modsync`/`registry` support still joins: it is told the *stand-in* for every custom state (next section) and never learns the custom ones.

## 5. Stand-ins (the vanilla fallback, and what the engine needs)

The world code (collision, light, shape, tool speed) does not know custom blocks. So every custom state has a **stand-in**: a vanilla block state whose
behaviour the custom state borrows (a "stone-like" block stands in as stone; a transparent decoration as glass). Where the server itself must treat a
cell as a block it asks `standInOf(stateId)`; the real state id is what is stored in chunk palettes and sent to Jester clients; vanilla clients are sent the
stand-in's id instead (a translation in the section/blockupdate packet writers, one lookup per distinct palette entry, not per block).

This keeps the first increment out of the lighting, collision and fluid code: they only ever see vanilla states.

## 6. Smallest working increment

"A plugin-registered custom block that a Jester client can see", in four steps, each testable on its own:

1. **Registry module + persisted id map** (`src/server/registry/dynamic.aowl`, `jester-registry.json`), with unit tests for stability (restart keeps ids, a removed mod's range is
   never reused). Pure, no world code.
2. **Plugin API**: `registerBlock(id, props, standIn)` callable only while the plugin loads (the registry is frozen after start-up), in both SDKs. Scenario: the
   server logs and a command reports the assigned `firstStateId`.
3. **Config-phase sync**: `jester:registry` table messages after the welcome, for clients that granted `modsync`; the scenario bot answers nothing and
   asserts the exact `modded.blockstates` line it received.
4. **Placing it**: `/setblock ns:name` and block updates carry the real id to Jester clients and the stand-in id to others (touches the packet writers for
   `block_update` and `section_blocks_update` and the chunk palette writer: **world/network code, to be agreed before it is changed**).

Steps 1 to 3 touch only the plugin manager, the network config code and new files. Step 4 is where the world/chunk code is touched and needs the
chunk-system owner's agreement; until then a custom block is visible in the client's tables but cannot be placed.

## 7. Open questions

* Block entities and NBT of a custom block (the first version has none).
* Where the client gets the *model and texture* of a custom block: `modded.sources` names asset jars on the player's own machine; whether the server may name a download URL in `jester-mods.json` is the modsync question, not this one.
* Items that are not block items need a model reference in the row; the client's `modded.items` row has only `rawId TAB name`. Needs the client side to decide how a model is bound.
* Tags: a custom block that should be mineable with a pickaxe needs the tag registry to take plugin rows; `getSynced` tags are static today.
* Entity types: a spawn needs the client to know the entity's size and renderer; deferred to a later version.
