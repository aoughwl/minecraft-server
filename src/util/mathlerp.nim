## Interpolation helpers used by noise sampling.
## Port of upstream's math/mod.rs (lerp/lerp2/lerp3/smoothstep family only -
## the rest of mod.rs is ported piecemeal elsewhere as it's needed).
##
## Rust's `lerp<T: Float>` is a single generic function. A `[T: SomeFloat]`
## Nimony generic hits a real compiler bug: it fails to resolve `-` (and
## arithmetic ops generally) on the generic parameter inside the proc body,
## even though `SomeFloat` is exactly the constraint that should permit it
## (reproduced standalone, filed as feedback). Worked around here with
## concrete float32/float64 overloads instead - the only two instantiations
## this codebase actually needs.

proc lerp*(delta, start, stop: float32): float32 {.inline.} =
  start + delta * (stop - start)

proc lerp*(delta, start, stop: float64): float64 {.inline.} =
  start + delta * (stop - start)

proc lerp2*(deltaX, deltaY, x0y0, x1y0, x0y1, x1y1: float32): float32 {.inline.} =
  lerp(deltaY, lerp(deltaX, x0y0, x1y0), lerp(deltaX, x0y1, x1y1))

proc lerp2*(deltaX, deltaY, x0y0, x1y0, x0y1, x1y1: float64): float64 {.inline.} =
  lerp(deltaY, lerp(deltaX, x0y0, x1y0), lerp(deltaX, x0y1, x1y1))

proc lerp3*(deltaX, deltaY, deltaZ: float32,
            x0y0z0, x1y0z0, x0y1z0, x1y1z0,
            x0y0z1, x1y0z1, x0y1z1, x1y1z1: float32): float32 {.inline.} =
  lerp(deltaZ,
       lerp2(deltaX, deltaY, x0y0z0, x1y0z0, x0y1z0, x1y1z0),
       lerp2(deltaX, deltaY, x0y0z1, x1y0z1, x0y1z1, x1y1z1))

proc lerp3*(deltaX, deltaY, deltaZ: float64,
            x0y0z0, x1y0z0, x0y1z0, x1y1z0,
            x0y0z1, x1y0z1, x0y1z1, x1y1z1: float64): float64 {.inline.} =
  lerp(deltaZ,
       lerp2(deltaX, deltaY, x0y0z0, x1y0z0, x0y1z0, x1y1z0),
       lerp2(deltaX, deltaY, x0y0z1, x1y0z1, x0y1z1, x1y1z1))

proc smoothstep*(x: float32): float32 {.inline.} =
  x * x * x * (x * (x * 6.0'f32 - 15.0'f32) + 10.0'f32)
