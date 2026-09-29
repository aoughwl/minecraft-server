## 3D vector argument type (float world/local coordinates).
## Port of upstream/command/src/argument_types/coordinates/vec3.rs
##
## Not wired into `ArgValue` yet, same reasoning as angle.nim/
## coordinates.nim/blockposarg.nim.

import cmderrors, string_reader, cmdsource, coordinates
import ../util/vector3

proc parseVec3*(r: var StringReader, centerIntegers: bool): CmdResult[Coordinates] =
  ## `centerIntegers` is upstream's `Vec3ArgumentType::Default` (true) vs.
  ## `::Uncorrected` (false).
  let (has, c) = peek(r)
  if has and c == '^':
    parseLocal(r)
  else:
    parseWorld(r, centerIntegers)

proc resolveVec3*(c: Coordinates, source: CommandSource): Vector3[float64] {.inline.} =
  resolve(c, source)
