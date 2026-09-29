## Round-trip test for the World stub, run via `nimony c -r`.

import std/assertions, std/syncio
import worldstub
import ../../world/tick

var w = newWorld()

# Air by default, including negative coordinates and never-touched sections.
assert w.getBlockState(blockPos(0, 0, 0)) == AirState
assert w.getBlockState(blockPos(-100, -50, 200)) == AirState

# Basic set/get within one section.
discard w.setBlockState(blockPos(1, 2, 3), 42'u32)
assert w.getBlockState(blockPos(1, 2, 3)) == 42'u32
assert w.getBlockState(blockPos(1, 2, 4)) == AirState  # neighbor unaffected

# Cross-section boundary (x=16 is the first cell of the next section over).
discard w.setBlockState(blockPos(15, 0, 0), 7'u32)
discard w.setBlockState(blockPos(16, 0, 0), 9'u32)
assert w.getBlockState(blockPos(15, 0, 0)) == 7'u32
assert w.getBlockState(blockPos(16, 0, 0)) == 9'u32

# Negative-coordinate section math (the floor-division trap).
discard w.setBlockState(blockPos(-1, -1, -1), 5'u32)
assert w.getBlockState(blockPos(-1, -1, -1)) == 5'u32
assert w.getBlockState(blockPos(-2, -1, -1)) == AirState
assert w.getBlockState(blockPos(-17, 0, 0)) == AirState  # different section than -1

# Previous-value return.
let prev = w.setBlockState(blockPos(1, 2, 3), 100'u32)
assert prev == 42'u32

echo "World stub: all checks passed"
