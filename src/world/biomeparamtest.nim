## Verifies biomeparam.nim against upstream's own `#[cfg(test)]` vectors
## (biome/mod.rs's `hash_seed_test`) plus sanity checks on Parameter/
## ParameterPoint distance math. Run with `nimony c -r`.

import std/assertions
import std/syncio
import biomeparam

# upstream: hash_seed(0) == 8794265229978523055
assert hashSeed(0'u64) == 8794265229978523055'i64, "hash_seed(0) mismatch"

# upstream: hash_seed((-777i64) as u64) == -1087248400229165450
# -777i64 as u64 is Rust's two's-complement reinterpretation.
let negSeed = cast[uint64](-777'i64)
assert hashSeed(negSeed) == -1087248400229165450'i64, "hash_seed(-777) mismatch"

# quantize/unquantize round-trip (within the resolution QUANTIZATION_FACTOR allows).
assert quantizeCoord(1.0'f32) == 10000'i64
assert quantizeCoord(-0.5'f32) == -5000'i64
assert abs(unquantizeCoord(10000'i64) - 1.0'f32) < 0.0001'f32

# Parameter distance: 0 inside the interval, positive gap outside it.
let p = parameterSpan(-1.0'f32, 1.0'f32)
assert distance(p, 0'i64) == 0
assert distance(p, quantizeCoord(2.0'f32)) == quantizeCoord(2.0'f32) - quantizeCoord(1.0'f32)
assert distance(p, quantizeCoord(-2.0'f32)) == quantizeCoord(-1.0'f32) - quantizeCoord(-2.0'f32)

# ParameterPoint fitness: a target exactly matching every axis interval's
# midpoint-with-zero-width point scores 0 (plus any offset squared).
let zeroPoint = parameterPoint(0.0'f32)
let pp = newParameterPoint(zeroPoint, zeroPoint, zeroPoint, zeroPoint, zeroPoint, zeroPoint, 0'i64)
let target = newTargetPoint(0, 0, 0, 0, 0, 0)
assert fitness(pp, target) == 0

let ppWithOffset = newParameterPoint(zeroPoint, zeroPoint, zeroPoint, zeroPoint, zeroPoint, zeroPoint, 5'i64)
assert fitness(ppWithOffset, target) == 25

echo "biomeparam: all checks passed"
