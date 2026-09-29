## A level-dependent numeric formula used throughout enchantment effects
## (e.g. "1 + 0.5 per level above 1", clamped/fractional/lookup-table
## variants).
## Ported from the upstream reference implementation's
## pumpkin-data/src/generated/enchantment.rs (the `LevelBasedValue` enum +
## its `calculate` method - the one piece of that otherwise-generated file
## that's genuinely hand-written formula logic, not table data, so it's
## worth porting on its own ahead of the rest of that crate).
##
## Upstream's variants hold `&'static Self` for recursive cases (Clamped's
## `value`, Fraction's `numerator`/`denominator`, Lookup's `fallback`) -
## static refs into a const arena built by the data-generator. Nimony has
## no equivalent const-arena story here, so those become `ref
## LevelBasedValue` (an ordinary heap ref); a recursive variant object
## needs indirection *somewhere*, and a ref is the direct Nimony analogue.

type
  LevelBasedValueKind* = enum
    lbvConstant
    lbvLinear
    lbvClamped
    lbvFraction
    lbvLevelsSquared
    lbvLookup

  LevelBasedValueRef* = ref LevelBasedValue
    ## A separately-named alias for the recursive-ref case-object fields
    ## below. Nimony's ARC-destructor codegen for a `ref T` field written
    ## inline inside `T`'s own case-object definition (direct
    ## self-recursion) hits a compiler bug - the generated destructor
    ## declaration and its call site disagree on the field's C type
    ## (`incompatible pointer type` at the C-codegen stage). Routing the
    ## recursive field through this named alias instead of writing `ref
    ## LevelBasedValue` inline avoids it.
  LevelBasedValue* = object
    case kind*: LevelBasedValueKind
    of lbvConstant:
      constVal*: float32
    of lbvLinear:
      base*: float32
      perLevelAboveFirst*: float32
    of lbvClamped:
      clampedValue*: LevelBasedValueRef
      clampMin*: float32
      clampMax*: float32
    of lbvFraction:
      numerator*: LevelBasedValueRef
      denominator*: LevelBasedValueRef
    of lbvLevelsSquared:
      added*: float32
    of lbvLookup:
      lookupValues*: seq[float32]
      fallback*: LevelBasedValueRef

proc calculate*(v: LevelBasedValue, level: int32): float32 =
  case v.kind
  of lbvConstant:
    v.constVal
  of lbvLinear:
    # `level.max(1) - 1` in the Rust source: levels below 1 don't produce a
    # negative multiplier.
    let effLevel = (if level > 1: level else: 1'i32) - 1'i32
    v.base + float32(effLevel) * v.perLevelAboveFirst
  of lbvClamped:
    let inner = calculate(v.clampedValue[], level)
    if inner < v.clampMin: v.clampMin
    elif inner > v.clampMax: v.clampMax
    else: inner
  of lbvFraction:
    let denom = calculate(v.denominator[], level)
    if denom == 0.0'f32:
      0.0'f32
    else:
      calculate(v.numerator[], level) / denom
  of lbvLevelsSquared:
    float32(level * level) + v.added
  of lbvLookup:
    # `(level - 1) as usize` indexing with `.get(idx)` (None on
    # out-of-range) falling back to `fallback.calculate(level)`. Also guard
    # against `level < 1`, which Rust's `usize` cast would otherwise wrap.
    let idx = level - 1
    if idx >= 0 and idx < int32(v.lookupValues.len):
      v.lookupValues[idx]
    else:
      calculate(v.fallback[], level)
