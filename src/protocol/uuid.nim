## UUID wire encoding used by the Minecraft protocol.
## Port of upstream/protocol/src/codec/uuid.rs plus the `get_uuid`/
## `write_uuid` halves of ser/mod.rs's NetworkReadExt/NetworkWriteExt.
##
## No general-purpose `Uuid` type exists anywhere in this port yet, so this
## is just the wire shape: 16 bytes, big-endian, as a (hi, lo) `uint64`
## pair - matching `netcodec.nim`'s `getUuidPair`/`writeUuidPair`, which
## this module re-exports under protocol-appropriate names.

import netcodec

export getUuidPair, writeUuidPair
