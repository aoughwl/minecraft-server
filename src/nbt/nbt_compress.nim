## Helpers for reading and writing gzip-compressed NBT data.
## Port of pumpkingmc/crates/pumpkin-nbt/src/nbt_compress.rs
##
## TODO(unblocked-but-unimplemented): Nimony's stdlib (`~/nimony/lib/std/`)
## has no gzip/zlib/deflate module at all (checked: no `zip`, `gzip`,
## `zlib`, or `compress` file anywhere under it), unlike Rust's `flate2`
## which this crate leans on directly. Two real options once this is
## needed for real chunk/playerdata I/O:
##   1. FFI-bind zlib (`{.importc.}`/`{.header: "zlib.h".}` against the
##      system zlib, which the C backend can already link against - Java
##      Edition's region/playerdata files are gzip- or zlib-wrapped NBT,
##      so this is needed eventually regardless).
##   2. Port a small pure-Nimony DEFLATE/gzip implementation.
## Neither is a quick add, so this file is a stub that establishes the
## call shape (mirroring `nbtdoc.nim`'s `Nbt` type) without faking
## compression. Do not have `readGzipCompoundTag`/`writeGzipCompoundTag`
## silently pass data through uncompressed - that would corrupt real
## on-disk NBT silently; leave them unimplemented and loud instead.

import nbtbase, nbtdoc, tag

proc readGzipCompoundTag*(input: seq[byte]): NbtResult[NbtCompound] =
  ## TODO: gzip-decompress `input` (see file header) before parsing.
  errRes[NbtCompound](nbtError(nekIncomplete,
    "gzip decompression not yet implemented (no zlib/gzip module in Nimony stdlib)"))

proc writeGzipCompoundTag*(compound: sink NbtCompound): NbtResult[seq[byte]] =
  ## TODO: gzip-compress the serialized bytes (see file header).
  errRes[seq[byte]](nbtError(nekIncomplete,
    "gzip compression not yet implemented (no zlib/gzip module in Nimony stdlib)"))
