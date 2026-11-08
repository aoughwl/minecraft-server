## Shared 3D gradient table for Perlin/simplex noise.
## Ported from upstream's noise/mod.rs.

type
  Gradient* = object
    x*, y*, z*: float64

const Gradients*: array[16, Gradient] = [
  Gradient(x: 1.0, y: 1.0, z: 0.0),
  Gradient(x: -1.0, y: 1.0, z: 0.0),
  Gradient(x: 1.0, y: -1.0, z: 0.0),
  Gradient(x: -1.0, y: -1.0, z: 0.0),
  Gradient(x: 1.0, y: 0.0, z: 1.0),
  Gradient(x: -1.0, y: 0.0, z: 1.0),
  Gradient(x: 1.0, y: 0.0, z: -1.0),
  Gradient(x: -1.0, y: 0.0, z: -1.0),
  Gradient(x: 0.0, y: 1.0, z: 1.0),
  Gradient(x: 0.0, y: -1.0, z: 1.0),
  Gradient(x: 0.0, y: 1.0, z: -1.0),
  Gradient(x: 0.0, y: -1.0, z: -1.0),
  Gradient(x: 1.0, y: 1.0, z: 0.0),
  Gradient(x: 0.0, y: -1.0, z: 1.0),
  Gradient(x: -1.0, y: 1.0, z: 0.0),
  Gradient(x: 0.0, y: -1.0, z: -1.0),
]

proc dot*(g: Gradient, x, y, z: float64): float64 {.inline.} =
  g.x * x + g.y * y + g.z * z
