## Verifies gen_noise_router.nim's generated output is internally
## consistent. NOT a check against real on-disk `_class`-tagged JSON - see
## gen_noise_router.nim's doc comment for why no such input was located in
## this pass. Actually run via `nimony c -r`, not just checked.

import std/[syncio, assertions]
import "../generated/noise_router"

var count = 0
for k in low(DensityFunctionKind) .. high(DensityFunctionKind):
  let jsonType = densityFunctionKindToJsonType(k)
  let (ok, back) = densityFunctionKindFromJsonType(jsonType)
  assert ok, "round-trip lookup failed for " & jsonType
  assert back == k, "round-trip mismatch for " & jsonType
  count += 1

assert count == 26, "expected 26 DensityFunctionKind variants, got " & $count

# spot-check a few of the renamed ones specifically
assert densityFunctionKindToJsonType(dfkWrapper) == "Wrapping"
assert densityFunctionKindToJsonType(dfkBinary) == "BinaryOperation"
assert densityFunctionKindToJsonType(dfkClampedYGradient) == "YClampedGradient"

let (badOk, _) = densityFunctionKindFromJsonType("NotARealKind")
assert not badOk, "unknown json type should not resolve"

echo "noise_router: all " & $count & " kinds round-trip correctly"
