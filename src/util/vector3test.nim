## Ad-hoc smoke test for vector3.nim's chunk-pos packing, run manually with
## `nimony c -r src/util/vector3test.nim`.
import std/assertions, std/syncio
import vector3

let samples = [
  vec3[int32](0, 0, 0),
  vec3[int32](1, 2, 3),
  vec3[int32](-1, -2, -3),
  vec3[int32](2097151, 524287, 2097151),   # max positive 22/20/22-bit fields
  vec3[int32](-2097152, -524288, -2097152), # min negative
]

for s in samples:
  let packed = packedChunkPos(s)
  let back = unpackedChunkPos(packed)
  assert back.x == s.x and back.y == s.y and back.z == s.z,
    "chunk pos round-trip failed for " & $s.x & "," & $s.y & "," & $s.z

let local = vec3[int32](7, 3, 9)
let pl = packedLocal(local)
assert pl == int16((7 shl 8) or (9 shl 4) or 3), "packed_local mismatch"

echo "vector3 packing checks passed"
