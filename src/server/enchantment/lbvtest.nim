## Smoke test for levelbasedvalue.nim against upstream's own semantics,
## run manually with `nimony c -r src/server/enchantment/lbvtest.nim`.
##
## Only exercises the non-recursive variants (Constant, Linear,
## LevelsSquared). The recursive variants (Clamped, Fraction, Lookup -
## the ones holding a `LevelBasedValueRef`) are semantically checked
## (`nimony check` passes clean on levelbasedvalue.nim, including their
## `calculate` branches) but NOT runtime-tested here: constructing a
## `LevelBasedValueRef` for them (via `new` + assign, or a ref-object
## constructor) hits a genuine Nimony C-codegen bug - the compiler
## generates a destructor call whose argument type doesn't match its own
## declaration for a self-recursive `ref` field inside a case object
## (`incompatible pointer type` at the C stage, in every construction
## style tried). This is a compiler limitation, not a bug in this file;
## reported upstream. Revisit this test once that's fixed.

import std/assertions
import std/syncio
import levelbasedvalue

# Constant
let c = LevelBasedValue(kind: lbvConstant, constVal: 5.0)
assert calculate(c, 1) == 5.0'f32
assert calculate(c, 99) == 5.0'f32

# Linear: base + (level.max(1) - 1) * perLevelAboveFirst
let lin = LevelBasedValue(kind: lbvLinear, base: 1.0, perLevelAboveFirst: 0.5)
assert calculate(lin, 1) == 1.0'f32
assert calculate(lin, 3) == 2.0'f32  # 1.0 + 2*0.5
assert calculate(lin, 0) == 1.0'f32  # level.max(1) clamps to 1

# LevelsSquared: level*level + added
let sq = LevelBasedValue(kind: lbvLevelsSquared, added: 1.0)
assert calculate(sq, 3) == 10.0'f32  # 9 + 1

echo "levelbasedvalue non-recursive-variant checks passed"
