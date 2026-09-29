## Block-position argument type (integral world/local coordinates).
## Port of upstream/command/src/argument_types/coordinates/block_pos.rs
##
## `get_loaded_block_pos`/`get_spawnable_pos`'s world-chunk-loaded/spawn
## checks need a real `World`/`Level` beyond `src/server/world/worldstub.nim`'s
## current surface, so only `parseBlockPos`/`resolveBlockPos` (the pure
## parse+resolve half every variant needs) and `isValidBlockPos` (upstream's
## free function, genuinely self-contained) are ported here. Not wired
## into `ArgValue` yet, same reasoning as angle.nim/coordinates.nim.

import cmderrors, string_reader, cmdsource, coordinates

const
  MaxHorizontal = 30_000_000
  MaxVertical = 20_000_000

proc parseBlockPos*(r: var StringReader): CmdResult[Coordinates] =
  let (has, c) = peek(r)
  if has and c == '^':
    parseLocal(r)
  else:
    parseWorldIntegers(r)

proc resolveBlockPos*(c: Coordinates, source: CommandSource): (int32, int32, int32) =
  let v = resolve(c, source)
  # Port of `BlockPos::floored_v`: component-wise floor to the containing block.
  proc flooredI32(x: float64): int32 =
    var f = x
    if f < 0 and f != float64(int64(f)):
      f = float64(int64(f)) - 1.0
    else:
      f = float64(int64(f))
    int32(f)
  (flooredI32(v.x), flooredI32(v.y), flooredI32(v.z))

proc isValidBlockPos*(x, y, z: int32): bool =
  x > -MaxHorizontal and x < MaxHorizontal and
    z > -MaxHorizontal and z < MaxHorizontal and
    y > -MaxVertical and y < MaxVertical
