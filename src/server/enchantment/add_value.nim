## Ported from the upstream reference implementation's
## pumpkin/src/enchantment/effects/add_value.rs

import levelbasedvalue

type
  AddValue* = object
    value*: LevelBasedValue

proc newAddValue*(value: sink LevelBasedValue): AddValue =
  AddValue(value: value)

proc process*(e: AddValue, level: int32, currentValue: float32): float32 =
  currentValue + calculate(e.value, level)
