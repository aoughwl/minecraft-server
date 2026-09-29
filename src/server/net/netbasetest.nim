## Verifies netbase.nim's `isValidPlayerName`/`decrementPendingBytes` against
## upstream's own `#[cfg(test)]` vectors from `net/mod.rs`'s `tests` module.
## Run with `nimony c -r src/server/net/netbasetest.nim`.

import std/assertions
import std/syncio
import netbase

# --- isValidPlayerName -------------------------------------------------

assert isValidPlayerName("player_name_1234"), "valid_max_length_ascii"
assert isValidPlayerName("GamerX"), "valid_short_ascii"
assert isValidPlayerName("!-@#$%.^&*_+-="), "valid_with_punctuation"
assert isValidPlayerName("玩家一号"), "valid_unicode_chinese (4 chars, 12 bytes)"
assert isValidPlayerName("Player_玩家"), "valid_mixed_chars"
assert not isValidPlayerName("this_name_is_too_long"), "invalid_length_ascii_over (21 bytes)"
assert not isValidPlayerName("超长玩家名称哈哈"), "invalid_length_unicode_over (8 chars, 24 bytes)"
assert not isValidPlayerName("Player Name"), "invalid_contains_space"
assert isValidPlayerName(""), "invalid_empty_string (upstream: empty is valid)"
assert not isValidPlayerName("Player\0Name"), "invalid_contains_null"
assert not isValidPlayerName("Player\nName"), "invalid_contains_newline"
assert not isValidPlayerName("Player" & char(127) & "Name"), "invalid_contains_del"

# --- decrementPendingBytes ----------------------------------------------

block:
  var counter: uint = 100
  decrementPendingBytes(counter, 40)
  assert counter == 60, "decrement_pending_bytes_saturating: 100-40"
  decrementPendingBytes(counter, 100)
  assert counter == 0, "decrement_pending_bytes_saturating: underflow clamps to 0"

# --- offlineUuid ----------------------------------------------------------
# No upstream test vector for offline_uuid exists in net/mod.rs itself, but
# it must be deterministic and non-degenerate.

block:
  let a = offlineUuid("Notch")
  let b = offlineUuid("Notch")
  let c = offlineUuid("Herobrine")
  assert a == b, "offlineUuid must be deterministic for the same username"
  assert a != c, "offlineUuid must differ for different usernames"
  assert not (a.hi == 0 and a.lo == 0), "offlineUuid should not be all-zero for a real name"

# --- defaultPlayerConfig ---------------------------------------------------

block:
  let cfg = defaultPlayerConfig()
  assert cfg.locale == "en_us"
  assert cfg.viewDistance == 8'u8
  assert cfg.chatMode == cmEnabled
  assert cfg.chatColors == true
  assert cfg.skinParts == 0x7F'u8
  assert cfg.mainHand == hRight
  assert cfg.textFiltering == false
  assert cfg.serverListing == false

echo "all net/mod.rs pure-logic checks passed"
