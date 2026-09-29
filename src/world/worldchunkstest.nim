## Real behavior test for worldchunks.nim, run via `nimony c -r`. No
## import of entity.nim anywhere in this file's dependency graph, so
## it's genuinely runtime-proven, unaffected by the closures-through-
## vtables crash (NIMONY-COMPILER-BUGS.md #1).

import std/[assertions, syncio]
import worldchunks

const
  AirState: uint32 = 0'u32
  StoneState: uint32 = 1'u32

let w = newWorldChunks(24, -64'i32, AirState, StoneState)

assert not isChunkLoaded(w, (cx: 0'i32, cz: 0'i32))
assert loadedChunkCount(w) == 0

## Writing auto-loads the containing column.
setBlockState(w, 5'i32, 0'i32, 5'i32, StoneState)
assert isChunkLoaded(w, (cx: 0'i32, cz: 0'i32))
assert loadedChunkCount(w) == 1
assert getBlockState(w, 5'i32, 0'i32, 5'i32) == StoneState

## Unread blocks in the same column default to air.
assert getBlockState(w, 6'i32, 0'i32, 5'i32) == AirState

## A different column is tracked separately.
setBlockState(w, 20'i32, 10'i32, 5'i32, StoneState) ## chunk (1, 0)
assert isChunkLoaded(w, (cx: 1'i32, cz: 0'i32))
assert loadedChunkCount(w) == 2
assert getBlockState(w, 20'i32, 10'i32, 5'i32) == StoneState
assert getBlockState(w, 5'i32, 0'i32, 5'i32) == StoneState ## first column untouched

## Negative coordinates land in the correct (negative) chunk, not off by
## one toward zero - the exact trap chunkPosOf's arm-shift math is meant
## to avoid.
setBlockState(w, -1'i32, 0'i32, -1'i32, StoneState) ## chunk (-1, -1)
assert isChunkLoaded(w, (cx: -1'i32, cz: -1'i32))
assert not isChunkLoaded(w, (cx: 0'i32, cz: -1'i32))
assert getBlockState(w, -1'i32, 0'i32, -1'i32) == StoneState
assert getBlockState(w, -16'i32, 0'i32, -16'i32) == AirState ## same column, different cell

## Unloading removes exactly the targeted column.
assert unloadChunk(w, (cx: 0'i32, cz: 0'i32))
assert not isChunkLoaded(w, (cx: 0'i32, cz: 0'i32))
assert isChunkLoaded(w, (cx: 1'i32, cz: 0'i32))
assert loadedChunkCount(w) == 2 ## the (1,0) and (-1,-1) columns remain
assert not unloadChunk(w, (cx: 99'i32, cz: 99'i32)) ## nothing to remove

echo "worldchunks: all checks passed"
