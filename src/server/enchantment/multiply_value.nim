## Ported from the upstream reference implementation's
## pumpkin/src/enchantment/effects/multiply_value.rs

import levelbasedvalue

type
  MultiplyValue* = object
    factor*: LevelBasedValue

proc newMultiplyValue*(factor: sink LevelBasedValue): MultiplyValue =
  MultiplyValue(factor: factor)

proc process*(e: MultiplyValue, level: int32, currentValue: float32): float32 =
  currentValue * calculate(e.factor, level)
