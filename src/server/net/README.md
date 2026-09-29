# `net/` — connection layer

Port target: upstream's `net/` (~19.5k lines across ~110 files: 733-line
`mod.rs`, per-edition state machines under `java/`/`bedrock/`, and
hundreds of individual packet handler files, mostly 8-100 lines each).

## What's here

`netbase.nim` — the plain-data/pure-function slice of `mod.rs`:

- `GameProfile`/`PropertyValue`/`ProfileAction`/`ChatMode`/`Hand`/
  `PlayerConfig` (+ `defaultPlayerConfig`) — the shape of "who is this
  client and what did they ask for". `properties` is a plain `seq` rather
  than upstream's `ArcSwap<Vec<Property>>` (no shared-mutation model
  exists yet in this port).
- `PacketHandlerResult` — `Stop` / `ReadyToPlay(profile, config)`.
- `MaxPendingBytes`, `decrementPendingBytes` — saturating byte-counter
  arithmetic.
- `EncryptionErrorKind` — the error enum's shape (its real use site, RSA
  shared-secret decryption, is blocked on RSA not existing in the sibling
  `../jwt` library yet).
- `isValidPlayerName` — byte-range scan instead of upstream's Unicode
  codepoint scan; verified against every one of upstream's own
  `#[cfg(test)]` vectors in `netbasetest.nim` (`nimony c -r`, all pass) -
  **caught a real bug this way**: an off-by-one on the space byte
  (`0x20`) that the "no space" test vector alone surfaced. Documented gap:
  doesn't implement Rust's full `char::is_control()` (misses the C1
  control block, U+0080-U+009F), which no upstream test exercises either.
- `offlineUuid` — SHA-256(username)[0..16], no version/variant bit fixup,
  matching upstream's actual (not spec-compliant) behavior exactly. Uses
  this port's own SHA-256 from the sibling `jwt` library (already the
  source for `hash_seed` in `src/world/biomeparam.nim`).
- `PlayerUuid` — a `(hi, lo): (uint64, uint64)` tuple, matching
  `src/protocol/uuid.nim`'s existing wire-shape convention rather than
  inventing a second UUID representation.

`chatmsg.nim` — the plain-data/pure-logic slice of `net/chat/mod.rs`
(432 lines): `FilterMask` (pass-through/fully-filtered/partially-filtered,
with the `#`-redaction `apply` logic), `SignedMessageLink`/
`SignedMessageBody`, `PlayerChatMessage` (construction, filtering,
signature removal, all the pure accessors), and `OutgoingChatMessage`'s
`create`/`content` split (system messages become "disguised", player
messages stay attributed). No `TextComponent` type exists in this port
yet, so every `TextComponent` field is a plain `string`, matching
`cmdsource.nim`'s/`eventdata.nim`'s convention. `send_to_player` (the
packet-construction/player-mutation tail) is NOT ported - needs `Player`'s
chat-session/signature-cache state and the `CPlayerChatMessage`/`SText`
packet types, none of which exist yet; the call site is noted in-file for
whoever wires that up. `chatmsgtest.nim` verifies all of the above for
real (`nimony c -r`, no `entity.nim` dependency so unaffected by the
closures-through-vtables crash) - genuine proof, not just a check pass.

## Why the rest isn't ported

1. **Everything above `mod.rs`'s pure-data slice is `Arc<..>`-shared and
   tokio-task-driven.** `ClientPlatform`, `JavaClient`, `BedrockClient`,
   `PendingConnection` are all built around concurrent mutable state and
   async I/O with no Nimony shape decided yet - the same
   tick-loop/concurrency gap `src/scheduler/` and `src/plugin_runtime/`
   already flagged and deferred. `net/` is one of the modules that would
   actually need to make that call, not just wait on it.
2. **The hundreds of individual packet handlers (`java/play/*.rs`,
   `bedrock/play/*.rs`, etc.) all need `Player`/`World`/`Server`** from
   elsewhere in this crate to do anything - they're glue between "a packet
   arrived" and "mutate game state", not self-contained logic. Most are
   8-50 lines specifically because nearly everything they do is a method
   call on one of those unported types.
3. **`handle_handshake` (`java/handshake.rs`, 51 lines)** was the other
   near-miss for this pass - version comparison + connection-state
   transition, genuinely small and mostly pure - but it reads
   `CURRENT_MC_VERSION`/`LOWEST_SUPPORTED_MC_VERSION` and translation-key
   constants from the still-unported `data` registry and calls
   `TextComponent`/`translate_cross` from `util::text` (also unported, see
   the `util` entry in the main README). Worth revisiting once either of
   those lands. **Update:** the *version* half of this blocker is now
   gone - `src/util/javaversion.nim` gained `protocolVersion`/
   `fromProtocol`/`supportsConfigurationState`/`isModern`/`hasRegistries`/
   `displayName` (direct ports of `version.rs`'s real methods, verified in
   `javaversiontest.nim` via `nimony c -r`) plus hand-copied
   `CurrentMcVersion`/`LowestSupportedMcVersion` constants (both `V_26_3`
   upstream at time of writing - `pumpkin-data`'s `packet.rs` generates
   these from one line each, not worth a whole codegen pass for two
   constants). `handle_handshake` itself is still blocked purely on
   `TextComponent`/`translate_cross`/`ConnectionState.store`'s
   `PendingConnection` state, not on version math anymore.
4. **Every Bedrock-specific file** (`bedrock/nethernet/*` - WebRTC-based
   peer discovery/signaling for Bedrock's NetherNet transport, ~1.7k lines
   alone) is a different protocol/transport family entirely, lower
   priority than Java Edition support.

## Suggested next steps

1. `authentication.rs` (513 lines) - once `../jwt`'s root-of-trust chain
   walk (flagged as blocked in `src/auth/README.md`... actually
   `src/auth/jwt.nim`'s doc comment) exists, this is where it gets called
   from the actual login flow. Worth reading even before that lands, to
   understand the exact call shape needed.
2. ~~`chat/mod.rs` (432 lines)~~ - done, see `chatmsg.nim` above. The
   remaining piece (`send_to_player`) needs `Player`'s chat-session state.
3. Once `server/`'s `Server`/`World` design pass happens (see
   `src/server/README.md`'s suggested-next-steps), `java/handshake.rs` and
   the smallest `java/login/*.rs` files become tractable - they're mostly
   blocked on registry/text lookups, not architecture.
