## World/local coordinate parsing shared by the position/vector argument
## types (`block_pos`, `vec3`, `vec2`, `column_pos`, `rotation`).
## Port of upstream/command/src/argument_types/coordinates/mod.rs
##
## Simplification: upstream's `Coordinates::resolve` for local coordinates
## uses `source.entity_anchor().position_at_source(source)`, which offsets
## by the source's eye height when the anchor is `Eyes`. No real
## entity/player eye-height plumbing reaches `CommandSource` yet (it's a
## plain position/rotation pair, see cmdsource.nim), so this approximates
## the eye offset with vanilla Java Edition's standing eye height
## (1.62 blocks) rather than a per-entity value - correct for a
## standing player, not for a crouching one or a non-player source.
## Documented rather than silently wrong.

import std/[math, strutils]
import cmderrors, string_reader, cmdnumbers, cmdsource
import ../util/vector2, ../util/vector3

const StandingEyeHeight = 1.62

type
  WorldCoordinateKind* = enum
    wckAbsolute
    wckRelative

  WorldCoordinate* = object
    kind*: WorldCoordinateKind
    value*: float64

  CoordinatesKind* = enum
    cokWorld
    cokLocal

  Coordinates* = object
    case kind*: CoordinatesKind
    of cokWorld:
      world*: Vector3[WorldCoordinate]
    of cokLocal:
      left*, up*, forward*: float64

proc newWorldCoordinate*(isRelative: bool, value: float64): WorldCoordinate =
  WorldCoordinate(kind: (if isRelative: wckRelative else: wckAbsolute), value: value)

proc isRelative*(w: WorldCoordinate): bool {.inline.} =
  w.kind == wckRelative

proc resolve*(w: WorldCoordinate, origin: float64): float64 =
  case w.kind
  of wckAbsolute: w.value
  of wckRelative: origin + w.value

proc consumeRelativeStart(r: var StringReader): bool =
  let (has, c) = peek(r)
  if has and c == '~':
    skip(r)
    true
  else:
    false

proc parseWorldCoord*(r: var StringReader, centerIntegers: bool): CmdResult[WorldCoordinate] =
  let (hasCaret, c) = peek(r)
  if hasCaret and c == '^':
    return cmdErr[WorldCoordinate](cekInvalidDouble, "Mixed relative and local coordinates (unsupported)")
  if not canReadByte(r):
    return cmdErr[WorldCoordinate](cekExpectedDouble, "Incomplete (expected) double")
  let isRel = consumeRelativeStart(r)
  let i = r.cursor()
  var value = 0.0
  let (hasNext, next) = peek(r)
  if hasNext and next != ' ':
    let dr = readDouble(r)
    if not dr.isOk:
      return cmdErr[WorldCoordinate](dr.error.kind, dr.error.message)
    value = dr.value
  let slice = r.str()[i ..< r.cursor()]
  if isRel and slice.len == 0:
    return cmdOk[WorldCoordinate](newWorldCoordinate(true, 0.0))
  if slice.find('.') < 0 and not isRel and centerIntegers:
    value += 0.5
  cmdOk[WorldCoordinate](newWorldCoordinate(isRel, value))

proc parseWorldCoordInteger*(r: var StringReader): CmdResult[WorldCoordinate] =
  let (hasCaret, c) = peek(r)
  if hasCaret and c == '^':
    return cmdErr[WorldCoordinate](cekInvalidInt, "Mixed relative and local coordinates (unsupported)")
  if not canReadByte(r):
    return cmdErr[WorldCoordinate](cekExpectedInt, "Incomplete (expected) integer")
  let isRel = consumeRelativeStart(r)
  var value = 0.0
  let (hasNext, next) = peek(r)
  if hasNext and next != ' ':
    if isRel:
      let dr = readDouble(r)
      if not dr.isOk:
        return cmdErr[WorldCoordinate](dr.error.kind, dr.error.message)
      value = dr.value
    else:
      let ir = readInt(r)
      if not ir.isOk:
        return cmdErr[WorldCoordinate](ir.error.kind, ir.error.message)
      value = float64(ir.value)
  cmdOk[WorldCoordinate](newWorldCoordinate(isRel, value))

proc checkForSpace(r: var StringReader, i: int, value: WorldCoordinate): CmdResult[WorldCoordinate] =
  let (has, c) = peek(r)
  if has and c == ' ':
    skip(r)
    cmdOk[WorldCoordinate](value)
  else:
    setCursor(r, i)
    cmdErr[WorldCoordinate](cekExpectedDouble, "Incomplete world coordinates")

proc parseWorld*(r: var StringReader, centerIntegers: bool): CmdResult[Coordinates] =
  let i = r.cursor()
  let c1r = parseWorldCoord(r, centerIntegers)
  if not c1r.isOk: return cmdErr[Coordinates](c1r.error.kind, c1r.error.message)
  let c1s = checkForSpace(r, i, c1r.value)
  if not c1s.isOk: return cmdErr[Coordinates](c1s.error.kind, c1s.error.message)
  # The Y coordinate is never centered.
  let c2r = parseWorldCoord(r, false)
  if not c2r.isOk: return cmdErr[Coordinates](c2r.error.kind, c2r.error.message)
  let c2s = checkForSpace(r, i, c2r.value)
  if not c2s.isOk: return cmdErr[Coordinates](c2s.error.kind, c2s.error.message)
  let c3r = parseWorldCoord(r, centerIntegers)
  if not c3r.isOk: return cmdErr[Coordinates](c3r.error.kind, c3r.error.message)
  cmdOk[Coordinates](Coordinates(kind: cokWorld,
    world: Vector3[WorldCoordinate](x: c1s.value, y: c2s.value, z: c3r.value)))

proc parseWorldIntegers*(r: var StringReader): CmdResult[Coordinates] =
  let i = r.cursor()
  let c1r = parseWorldCoordInteger(r)
  if not c1r.isOk: return cmdErr[Coordinates](c1r.error.kind, c1r.error.message)
  let c1s = checkForSpace(r, i, c1r.value)
  if not c1s.isOk: return cmdErr[Coordinates](c1s.error.kind, c1s.error.message)
  let c2r = parseWorldCoordInteger(r)
  if not c2r.isOk: return cmdErr[Coordinates](c2r.error.kind, c2r.error.message)
  let c2s = checkForSpace(r, i, c2r.value)
  if not c2s.isOk: return cmdErr[Coordinates](c2s.error.kind, c2s.error.message)
  let c3r = parseWorldCoordInteger(r)
  if not c3r.isOk: return cmdErr[Coordinates](c3r.error.kind, c3r.error.message)
  cmdOk[Coordinates](Coordinates(kind: cokWorld,
    world: Vector3[WorldCoordinate](x: c1s.value, y: c2s.value, z: c3r.value)))

proc parseLocalNumber(r: var StringReader, i: int): CmdResult[float64] =
  if not canReadByte(r):
    return cmdErr[float64](cekExpectedDouble, "Incomplete (expected) double")
  let (has, c) = peek(r)
  if not (has and c == '^'):
    setCursor(r, i)
    return cmdErr[float64](cekInvalidDouble, "Mixed local and world coordinates")
  skip(r)
  var value = 0.0
  let (hasNext, next) = peek(r)
  if hasNext and next != ' ':
    let dr = readDouble(r)
    if not dr.isOk:
      return cmdErr[float64](dr.error.kind, dr.error.message)
    value = dr.value
  cmdOk[float64](value)

proc parseLocalSingle(r: var StringReader, i: int): CmdResult[float64] =
  let nr = parseLocalNumber(r, i)
  if not nr.isOk:
    return nr
  let (has, c) = peek(r)
  if has and c == ' ':
    skip(r)
    cmdOk[float64](nr.value)
  else:
    setCursor(r, i)
    cmdErr[float64](cekExpectedDouble, "Incomplete local coordinates")

proc parseLocal*(r: var StringReader): CmdResult[Coordinates] =
  let i = r.cursor()
  let leftR = parseLocalSingle(r, i)
  if not leftR.isOk: return cmdErr[Coordinates](leftR.error.kind, leftR.error.message)
  let upR = parseLocalSingle(r, i)
  if not upR.isOk: return cmdErr[Coordinates](upR.error.kind, upR.error.message)
  let fwdR = parseLocalNumber(r, i)
  if not fwdR.isOk: return cmdErr[Coordinates](fwdR.error.kind, fwdR.error.message)
  cmdOk[Coordinates](Coordinates(kind: cokLocal, left: leftR.value, up: upR.value, forward: fwdR.value))

proc convertLocalCoordinates*(left, up, forward: float64, rotation: Vector2[float32]): Vector3[float64] =
  let pitch = rotation.x
  let yaw = rotation.y
  let y = degToRad(float64(yaw) + 90.0)
  let yCos = cos(y)
  let ySin = sin(y)
  let x = degToRad(float64(-pitch))
  let xCos = cos(x)
  let xSin = sin(x)
  let xUp = degToRad(float64(-pitch) + 90.0)
  let xUpCos = cos(xUp)
  let xUpSin = sin(xUp)
  let forwardVec = Vector3[float64](x: yCos * xCos, y: xSin, z: ySin * xCos)
  let upVec = Vector3[float64](x: yCos * xUpCos, y: xUpSin, z: ySin * xUpCos)
  let leftVec = cross(forwardVec, upVec) * -1.0
  Vector3[float64](
    x: forwardVec.x * forward + upVec.x * up + leftVec.x * left,
    y: forwardVec.y * forward + upVec.y * up + leftVec.y * left,
    z: forwardVec.z * forward + upVec.z * up + leftVec.z * left,
  )

proc anchorPositionApprox(s: CommandSource): Vector3[float64] =
  if s.entityAnchor == eaEyes:
    Vector3[float64](x: s.position.x, y: s.position.y + StandingEyeHeight, z: s.position.z)
  else:
    s.position

proc resolve*(c: Coordinates, s: CommandSource): Vector3[float64] =
  case c.kind
  of cokWorld:
    Vector3[float64](
      x: resolve(c.world.x, s.position.x),
      y: resolve(c.world.y, s.position.y),
      z: resolve(c.world.z, s.position.z),
    )
  of cokLocal:
    let start = anchorPositionApprox(s)
    add(convertLocalCoordinates(c.left, c.up, c.forward, s.rotation), start)

proc rotationOf*(c: Coordinates, s: CommandSource): Vector2[float32] =
  case c.kind
  of cokWorld:
    Vector2[float32](
      x: float32(resolve(c.world.x, float64(s.rotation.x))),
      y: float32(resolve(c.world.y, float64(s.rotation.y))),
    )
  of cokLocal:
    Vector2[float32](x: 0.0'f32, y: 0.0'f32)

proc isRelativeAxis*(c: Coordinates, axis: Axis): bool =
  case c.kind
  of cokWorld: isRelative(getAxis(c.world, axis))
  of cokLocal: true
