## Port of upstream/config/src/whitelist.rs
## Upstream's `Uuid` comes from the external `uuid` crate; no Nimony UUID
## module exists yet anywhere in this port, so it's represented here as a
## plain 16-byte value. TODO: replace with a shared `Uuid` type (parsing,
## formatting, v4 generation) once one exists - probably belongs next to
## wherever `util`'s UUID-touching code lands, not duplicated here.

type
  Uuid* = array[16, byte]

  WhitelistEntry* = object
    uuid*: Uuid
    name*: string

proc newWhitelistEntry*(uuid: Uuid, name: string): WhitelistEntry =
  WhitelistEntry(uuid: uuid, name: name)
