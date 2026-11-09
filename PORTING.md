# Porting guide

How this server is finished. Read this before porting anything.

## Source and target

- **Source of truth:** the upstream Rust server at commit `b7ccef5b2` (2026-08-02), kept checked out read-only at
  `../ref/pumpkin-1.21.11`. It has packet tables for 1.20.5 through 26.2. A newer checkout, `../ref/pumpkin`, is
  only for logic added since then, after the pinned tree is done.
- **Wire target:** Minecraft 1.21.11, protocol 774, because that is the game client we ship. Other versions in the
  tables stay ported where upstream gates on them, but 774 is what must work.
- **Licence:** derivative work under GPLv3, see `NOTICE.md`.

## How far along

`python tools/port_status.py` prints coverage per crate, and `--missing <crate>` lists what is left, largest first.
A file counts once a source here names its upstream path. So every port starts with
`## Port of <crate>/src/<path>.rs`, using the path in the pinned tree.

A file that is not whole says so on a line of its own, with what is missing:
`## PARTIAL: <crate>/src/<path>.rs - <what is not done and why>`.
Never write a stub that looks finished. `grep -rn PARTIAL src` is the honest list of remaining work.

## Rules

- Sources are `.aowl`. The language is aowlmony; say so in comments and docs.
- Follow upstream's module boundaries and logic. It is a translation, not a rewrite: same names in camelCase, same
  order of operations, same constants. Do not guess at a constant, a packet field or a wire order. Read it.
- Generated upstream data (`pumpkin-data/src/generated`) is not hand-ported. Write or extend a generator under
  `src/data_codegen` that reads `assets/` from the pinned tree and writes `src/generated/`.
- Traits become a `ref object` of `{.closure.}` fields, as `EntityBase` does. Async becomes plain calls driven by the
  tick loop or a worker. No `raise` at I/O boundaries: fallible calls return a result the caller checks.
- Every ported module gets a `<name>test.aowl` beside it that runs and exits non-zero on failure. Port upstream's own
  `#[test]` vectors where they exist. Known-answer checks beat round-trips, and a packet test asserts the exact bytes.
- No sleeping, no network, no game client in a unit test.

## Build and check

Use a private cache per worker; a shared one fails falsely. Paths are relative to the repo root.
This port needs aowlhexer d596bd9 or later: older ones crash on closures in object fields.

    aowlmony check --nimcache:<own dir> -p:src -p:../jwt/src -p:../compress/src -p:../compress <file>
    aowlmony c -r --cc:gcc --nimcache:<own dir> -o:<own exe> -p:src -p:<file's dir> -p:../jwt/src <test>

gcc from `C:\msys64\ucrt64\bin` must come first on PATH.

## Order

1. Protocol: packet ids, codecs, every java packet.
2. Login, configuration, registries, and the join into play.
3. Chunks: Anvil loading, chunk packets, lighting, and the chunk system.
4. Player and world: movement, block interaction, inventory, the tick loop.
5. Blocks, items, entities, commands, and world generation.
6. Plugins, Bedrock, RCON and the rest of `port_status.py`.
