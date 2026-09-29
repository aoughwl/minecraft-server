## Ported from the upstream reference implementation's
## pumpkin/src/enchantment/effects/set_value.rs

import levelbasedvalue

type
  SetValue* = object
    value*: LevelBasedValue

proc newSetValue*(value: sink LevelBasedValue): SetValue =
  SetValue(value: value)

proc process*(e: SetValue, level: int32): float32 =
  calculate(e.value, level)
