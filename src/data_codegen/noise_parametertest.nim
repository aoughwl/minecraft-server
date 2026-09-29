## Smoke test for the generated noise_parameter table. Run via
## `nimony c -r src/data_codegen/noise_parametertest.nim`.
import std/[assertions, syncio]
import "../generated/noise_parameter"

let all = allNoiseParameters()
assert all.len == 62, "expected 62 noise parameter entries, got " & $all.len

let (found, p) = idToParameters("minecraft:aquifer_barrier")
assert found
assert p.firstOctave == -3
assert p.amplitudes == @[1.0]
# Cross-checked against Python's hashlib.md5(b"minecraft:aquifer_barrier"):
# lo=16244762748638791999, hi=1391399305011792652 - exact match.
assert p.lo == 16244762748638791999'u64
assert p.hi == 1391399305011792652'u64

let (found2, p2) = idToParameters("temperature")
assert found2
assert p2.firstOctave == -10
assert p2.amplitudes == @[1.5, 0.0, 1.0, 0.0, 0.0, 0.0]

let (foundMissing, _) = idToParameters("minecraft:does_not_exist")
assert not foundMissing

echo "noise_parameter: all checks passed (", all.len, " entries)"
