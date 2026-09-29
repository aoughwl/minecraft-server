## Port of upstream/tools/pumpkin-codegen/src/chunk_view_lut.rs
##
## Unlike every other file in this directory, this one has no JSON input -
## it's pure math (concentric view-distance/Chebyshev-ring offset tables).
## Upstream computes it inside a `proc_macro2`/`quote!` build script so the
## tables are baked as `static` data with zero runtime cost. Nimony has no
## build-time codegen macros to reproduce that trick, and there's no
## external data file for a "generator" to read here, so this is simply
## the same computation ported directly as a module that builds its tables
## once at load time (`let ... = build...()` below) - behaviorally
## equivalent (same values, computed once, read many times), just computed
## at Nimony program startup instead of at Rust compile time.

const
  MaxViewDistance* = 32'u8
  MaxChebyshevRadius* = 48'u8

proc buildChunkViewLut(): seq[seq[(int8, int8)]] =
  ## Index `dist` (0..MaxViewDistance) -> relative chunk offsets within
  ## that view distance, sorted by squared distance from center.
  result = newSeq[seq[(int8, int8)]](int(MaxViewDistance) + 1)
  for dist in 0'u8 .. MaxViewDistance:
    if dist < 2:
      result[int(dist)] = @[]
      continue
    var positions: seq[(int8, int8)] = @[]
    let d = int64(dist)
    var z = -(d + 2)
    while z <= d + 2:
      var x = -(d + 2)
      while x <= d + 2:
        let relX = max(abs(x) - 2, 0)
        let relZ = max(abs(z) - 2, 0)
        if relX * relX + relZ * relZ < d * d:
          positions.add((int8(x), int8(z)))
        x += 1
      z += 1
    # Manual insertion sort by squared distance: known Nimony compiler bug
    # (seq[T].sort with a closure comparator crashes C-codegen when T is
    # an object with an enum field) doesn't apply to a plain tuple seq
    # like this one, but algorithm.sort's closure form has its own
    # sharp edges elsewhere in this port - stay closure-free to be safe.
    for i in 1 ..< positions.len:
      let key = positions[i]
      let keyDist = int32(key[0]) * int32(key[0]) + int32(key[1]) * int32(key[1])
      var j = i - 1
      while j >= 0:
        let curX = positions[j][0]
        let curZ = positions[j][1]
        let curDist = int32(curX) * int32(curX) + int32(curZ) * int32(curZ)
        if curDist <= keyDist:
          break
        let moved = (curX, curZ)
        positions[j + 1] = moved
        j -= 1
      positions[j + 1] = key
    result[int(dist)] = positions

let chunkViewLut* = buildChunkViewLut()

type
  ChebyshevTables = object
    offsets*: seq[(int8, int8)]
    ringStart*: seq[int]
    ringEnd*: seq[int]
    squareEnd*: seq[int]

proc buildChebyshev(): ChebyshevTables =
  result = ChebyshevTables(offsets: @[], ringStart: @[], ringEnd: @[], squareEnd: @[])
  var currentIdx = 0
  var r = 0'u8
  while r <= MaxChebyshevRadius:
    let ri = int8(r)
    let start = currentIdx
    if r == 0:
      result.offsets.add((0'i8, 0'i8))
      currentIdx += 1
    else:
      var x = -ri
      while x <= ri:
        result.offsets.add((x, -ri))
        result.offsets.add((x, ri))
        currentIdx += 2
        x += 1
      var z = -ri + 1
      while z <= ri - 1:
        result.offsets.add((-ri, z))
        result.offsets.add((ri, z))
        currentIdx += 2
        z += 1
    let stop = currentIdx
    result.ringStart.add(start)
    result.ringEnd.add(stop)
    result.squareEnd.add(stop)
    r += 1

let chebyshev* = buildChebyshev()

proc getChebyshevRing*(radius: uint8): seq[(int8, int8)] =
  let r = min(int(radius), int(MaxChebyshevRadius))
  chebyshev.offsets[chebyshev.ringStart[r] ..< chebyshev.ringEnd[r]]

proc getChebyshevSquare*(radius: uint8): seq[(int8, int8)] =
  let r = min(int(radius), int(MaxChebyshevRadius))
  chebyshev.offsets[0 ..< chebyshev.squareEnd[r]]
