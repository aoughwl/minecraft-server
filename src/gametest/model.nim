## Port of pumpkingmc/crates/pumpkin-gametest/src/model.rs
##
## `serde`/`serde_json` (Deserialize derives, `Value`) are skipped entirely -
## no decode layer is ported anywhere yet. `environment: Value` (arbitrary
## JSON) becomes a raw `string` placeholder holding the unparsed JSON text;
## replace with a real JSON value type once one exists in this port.

import rotation_stub

type
  TestType* = enum
    ttBlockBased
    ttFunction

proc serializedName*(t: TestType): string =
  case t
  of ttBlockBased: "minecraft:block_based"
  of ttFunction: "minecraft:function"

type
  GameTestRotation* = enum
    gtrNone
    gtrClockwise90
    gtrClockwise180
    gtrCounterclockwise90

proc serializedName*(r: GameTestRotation): string =
  case r
  of gtrNone: "none"
  of gtrClockwise90: "clockwise_90"
  of gtrClockwise180: "180"
  of gtrCounterclockwise90: "counterclockwise_90"

proc asBlockRotation*(r: GameTestRotation): Rotation =
  case r
  of gtrNone: rotNone
  of gtrClockwise90: rotClockwise90
  of gtrClockwise180: rotRotate180
  of gtrCounterclockwise90: rotCounterClockwise90

proc then*(self: GameTestRotation, extra: GameTestRotation): GameTestRotation =
  ## Combines the datapack's base rotation with an additional controller
  ## rotation. Mirrors vanilla `Rotation::getRotated`/`GameTestInfo` extra
  ## rotation.
  case then(asBlockRotation(self), asBlockRotation(extra))
  of rotNone: gtrNone
  of rotClockwise90: gtrClockwise90
  of rotRotate180: gtrClockwise180
  of rotCounterClockwise90: gtrCounterclockwise90

proc gameTestRotationFromSteps*(steps: int32): GameTestRotation =
  var m = steps mod 4
  if m < 0:
    m += 4
  case m
  of 0: gtrNone
  of 1: gtrClockwise90
  of 2: gtrClockwise180
  else: gtrCounterclockwise90

type
  GameTestDefinition* = object
    instanceType*: TestType
    environment*: string  ## Raw JSON text; see file header.
    structure*: string
    function*: string     ## Empty string stands in for `Option::None`.
    hasFunction*: bool
    maxTicks*: int32
    setupTicks*: int32
    required*: bool
    rotation*: GameTestRotation
    manualOnly*: bool
    maxAttempts*: int32
    requiredSuccesses*: int32
    skyAccess*: bool
    padding*: int32

proc newGameTestDefinition*(): GameTestDefinition =
  ## Upstream's serde `#[serde(default = ...)]` field defaults, applied
  ## when no deserializer exists yet to apply them for us.
  GameTestDefinition(
    instanceType: ttBlockBased,
    required: true,
    maxAttempts: 1,
    requiredSuccesses: 1,
  )

proc isValid*(d: GameTestDefinition): bool =
  let functionValid =
    case d.instanceType
    of ttBlockBased: true
    of ttFunction: d.hasFunction and d.function.len > 0

  functionValid and
    d.maxTicks > 0 and
    d.setupTicks >= 0 and
    d.maxAttempts > 0 and
    d.requiredSuccesses > 0 and
    d.padding >= 0 and d.padding <= 128
