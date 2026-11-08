## Port of upstream/gametest/src/error.rs
##
## `Assertion`'s `position: Option<BlockPos>` needs `util::math::
## position::BlockPos`, not yet ported (util's `math/` files remain).
## Represented here as an `(bool, x, y, z)` tuple rather than blocking on
## that - swap for the real `BlockPos` once `src/util/` has it.

type
  GameTestErrorKind* = enum
    gtekAssertion
    gtekTimeout
    gtekExhaustedAttempts
    gtekInvalidStructure
    gtekWorld

  GameTestError* = object
    case kind*: GameTestErrorKind
    of gtekAssertion:
      tick*: uint32
      hasPosition*: bool
      posX*, posY*, posZ*: int32
      message*: string
    of gtekTimeout:
      maxTicks*: uint32
    of gtekExhaustedAttempts:
      attempts*, successes*, requiredSuccesses*: uint32
      lastError*: string
    of gtekInvalidStructure:
      invalidStructureMsg*: string
    of gtekWorld:
      worldMsg*: string

  GameTestResult*[T] = object
    case isOk*: bool
    of true:
      value*: T
    of false:
      error*: GameTestError

proc ok*[T](value: sink T): GameTestResult[T] =
  GameTestResult[T](isOk: true, value: value)

proc errRes*[T](e: GameTestError): GameTestResult[T] =
  GameTestResult[T](isOk: false, error: e)

proc `$`*(e: GameTestError): string =
  case e.kind
  of gtekAssertion:
    "assertion failed at tick " & $e.tick & ": " & e.message
  of gtekTimeout:
    "test exceeded its maximum of " & $e.maxTicks & " ticks"
  of gtekExhaustedAttempts:
    "test exhausted " & $e.attempts & " attempts with " & $e.successes &
      " successes; " & $e.requiredSuccesses & " successes required: " & e.lastError
  of gtekInvalidStructure:
    e.invalidStructureMsg
  of gtekWorld:
    e.worldMsg
