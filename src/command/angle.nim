## Angle argument type (`Angle` value: a float32 plus a relative flag).
## Port of upstream/command/src/argument_types/coordinates/angle.rs
##
## `Angle` doesn't reduce to a single `ArgValue` primitive the way
## uuid/gamemode/identifier's validated text does, and `Coordinates`
## (coordinates.nim) is in the same boat for the same reason - so this
## stays a standalone parser, not wired into the `ArgumentType`/`ArgValue`
## vtable yet. Widening `ArgValue` with an `avkAngle`/`avkCoordinates`
## case (or moving to a payload-carrying variant scheme) is the real next
## step once a caller needs these hooked into the command tree; the
## parsing/resolution logic itself is real and independently testable now.

import std/math
import cmderrors, string_reader, cmdnumbers, cmdsource

type
  Angle* = object
    angle*: float32
    isRelative*: bool

proc newAngle*(angle: float32, isRelative: bool): Angle {.inline.} =
  Angle(angle: angle, isRelative: isRelative)

proc wrapDegrees(degrees: float32): float32 =
  ## Port of `pumpkin_util::math::wrap_degrees` (wraps into (-180, 180]).
  var d = degrees mod 360.0'f32
  if d >= 180.0'f32:
    d -= 360.0'f32
  if d < -180.0'f32:
    d += 360.0'f32
  d

proc getAngle*(a: Angle, source: CommandSource): float32 =
  let base = if a.isRelative: source.rotation.y else: 0.0'f32
  wrapDegrees(base + a.angle)

proc parseAngle*(r: var StringReader): CmdResult[Angle] =
  if not canReadByte(r):
    return cmdErr[Angle](cekExpectedFloat, "Incomplete angle")
  var isRel = false
  let (hasTilde, tilde) = peek(r)
  if hasTilde and tilde == '~':
    isRel = true
    skip(r)
  var angle: float32
  let (hasNext, next) = peek(r)
  if hasNext and next != ' ':
    let fr = readFloat(r)
    if not fr.isOk:
      return cmdErr[Angle](fr.error.kind, fr.error.message)
    angle = fr.value
  elif isRel:
    angle = 0.0'f32
  else:
    return cmdErr[Angle](cekExpectedFloat, "Incomplete angle")
  if angle.classify() == fcNan or angle.classify() == fcInf or angle.classify() == fcNegInf:
    return cmdErr[Angle](cekInvalidFloat, "Invalid angle")
  cmdOk[Angle](newAngle(angle, isRel))
