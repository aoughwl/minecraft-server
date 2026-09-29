## Numeric argument parsing built on `StringReader`.
## Port of `read_and_parse`/`read_int`/`read_long`/`read_float`/`read_double`
## in pumpkingmc/crates/pumpkin-command/src/string_reader.rs.

import std/parseutils
import cmderrors, string_reader

proc readInt*(r: var StringReader): CmdResult[int32] =
  let tokRes = readNumericToken(r, cekExpectedInt)
  if not tokRes.isOk:
    return cmdErr[int32](tokRes.error.kind, tokRes.error.message)
  var value: BiggestInt = 0
  let consumed = parseBiggestInt(tokRes.value, value)
  if consumed != tokRes.value.len or value < int32.low.BiggestInt or value > int32.high.BiggestInt:
    return cmdErr[int32](cekInvalidInt, "Invalid integer '" & tokRes.value & "'")
  cmdOk[int32](int32(value))

proc readLong*(r: var StringReader): CmdResult[int64] =
  let tokRes = readNumericToken(r, cekExpectedLong)
  if not tokRes.isOk:
    return cmdErr[int64](tokRes.error.kind, tokRes.error.message)
  var value: BiggestInt = 0
  let consumed = parseBiggestInt(tokRes.value, value)
  if consumed != tokRes.value.len:
    return cmdErr[int64](cekInvalidLong, "Invalid long '" & tokRes.value & "'")
  cmdOk[int64](int64(value))

proc readFloat*(r: var StringReader): CmdResult[float32] =
  let tokRes = readNumericToken(r, cekExpectedFloat)
  if not tokRes.isOk:
    return cmdErr[float32](tokRes.error.kind, tokRes.error.message)
  var value: BiggestFloat = 0.0
  let consumed = parseBiggestFloat(tokRes.value, value)
  if consumed != tokRes.value.len:
    return cmdErr[float32](cekInvalidFloat, "Invalid float '" & tokRes.value & "'")
  cmdOk[float32](float32(value))

proc readDouble*(r: var StringReader): CmdResult[float64] =
  let tokRes = readNumericToken(r, cekExpectedDouble)
  if not tokRes.isOk:
    return cmdErr[float64](tokRes.error.kind, tokRes.error.message)
  var value: BiggestFloat = 0.0
  let consumed = parseBiggestFloat(tokRes.value, value)
  if consumed != tokRes.value.len:
    return cmdErr[float64](cekInvalidDouble, "Invalid double '" & tokRes.value & "'")
  cmdOk[float64](value)
