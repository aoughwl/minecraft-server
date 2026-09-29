## Helpers for reading and writing gzip-compressed NBT data.
## Port of upstream/nbt/src/nbt_compress.rs
##
## Backed by the aoughwl `compress` library (../compress, added via
## nimony.paths), a one-shot `string -> string` gzip/Brotli/Zstd codec set
## over the system zlib/brotli/zstd. Its `gzipCompress`/`gzipDecompress`
## operate on `string`, so this file converts to/from `seq[byte]` at the
## boundary; `compress` signals failure by returning `""`, which this
## module turns into a proper `NbtResult` error rather than silently
## treating it as valid empty output.
##
## Verification status: this file and gziptest.nim compile clean, but
## full runtime round-trip verification was NOT achieved on this Windows
## dev machine. `compress`'s zlib binding hardcodes the Linux shared-object
## name `libz.so.1` via `{.dynlib.}` (no Windows name variant), so on
## Windows it fails to load by default. Making a same-format zlib DLL
## available under that exact literal filename gets past the load step,
## but the subsequent `deflateInit2_`/`deflate` calls then fail (returns
## nonzero) - a deeper ABI/calling-convention mismatch on Windows, not
## just a naming issue, and debugging that is `compress`'s own internals
## (a sibling project), out of scope here. `compress`'s own README targets
## Linux (`libz.so.1`/`libbrotlienc.so.1`/`libzstd.so.1`), so this is
## expected to work correctly on the project's actual Linux deployment
## target; it just couldn't be proven end-to-end from here. Re-run
## gziptest.nim on Linux to confirm before relying on this in production.

import nbtbase, nbtdoc, tag, serializer, deserializer
import compress

const MaxDecompressedSize = 64 * 1024 * 1024 ## matches upstream's 64 MiB cap

proc bytesToStr(data: seq[byte]): string =
  result = newString(data.len)
  for i, b in data:
    result[i] = char(b)

proc strToBytes(s: string): seq[byte] =
  result = newSeq[byte](s.len)
  for i, c in s:
    result[i] = byte(c)

proc readGzipCompoundTag*(input: seq[byte]): NbtResult[NbtCompound] =
  let compressed = bytesToStr(input)
  let decompressed = gzipDecompress(compressed, maxSize = MaxDecompressedSize)
  if decompressed.len == 0 and compressed.len != 0:
    # compress.nim signals a decode failure with "" - genuine empty-payload
    # gzip streams still carry a nonzero (header+trailer) compressed size,
    # so a nonempty input decompressing to "" is always the error case.
    return errRes[NbtCompound](incomplete("gzip decompression failed (bad stream or exceeded " &
      $MaxDecompressedSize & " byte limit)"))
  var reader = newNbtReader(nrmJava, strToBytes(decompressed))
  let nbtRes = read(reader)
  if not nbtRes.isOk:
    return errRes[NbtCompound](nbtRes.error)
  ok[NbtCompound](nbtRes.value.rootTag)

proc writeGzipCompoundTag*(compound: sink NbtCompound): NbtResult[seq[byte]] =
  let doc = newNbt("", compound)
  let raw = write(doc, nwmJava)
  let compressed = gzipCompress(bytesToStr(raw))
  if compressed.len == 0 and raw.len != 0:
    return errRes[seq[byte]](incomplete("gzip compression failed"))
  ok[seq[byte]](strToBytes(compressed))
