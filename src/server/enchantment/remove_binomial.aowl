## Ported from the upstream reference implementation's
## pumpkin/src/enchantment/effects/remove_binomial.rs

import levelbasedvalue
import std/random

type
  RemoveBinomial* = object
    chance*: LevelBasedValue

proc newRemoveBinomial*(chance: sink LevelBasedValue): RemoveBinomial =
  RemoveBinomial(chance: chance)

proc process*(e: RemoveBinomial, level: int32, currentValue: float32): float32 =
  let prob = calculate(e.chance, level)
  if float32(rand(1.0)) < prob:
    0.0'f32
  else:
    currentValue
