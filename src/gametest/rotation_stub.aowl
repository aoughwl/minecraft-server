## Local stand-in for `data::block_rotation::Rotation`.
## data (crates/data) is ~1.5M lines, almost all generated
## block/item/registry tables, and is intentionally deferred to the end of
## the porting order (see README) - its generator gets ported, not the
## generated output, once everything above it has settled. `Rotation`
## itself is hand-written and tiny, but block_rotation.rs also carries
## ~800 lines of block-property transform logic this crate doesn't need.
## Only the 4-way rotation enum and its `then` combinator (used by
## `GameTestRotation.then`) are copied here. TODO: replace this with an
## import of the real ported type once data's block_rotation.rs
## is ported, rather than keeping two copies in sync.

type
  Rotation* = enum
    rotNone
    rotClockwise90
    rotRotate180
    rotCounterClockwise90

proc then*(self: Rotation, other: Rotation): Rotation =
  case self
  of rotNone: other
  of rotClockwise90:
    case other
    of rotNone: rotClockwise90
    of rotClockwise90: rotRotate180
    of rotRotate180: rotCounterClockwise90
    of rotCounterClockwise90: rotNone
  of rotRotate180:
    case other
    of rotNone: rotRotate180
    of rotClockwise90: rotCounterClockwise90
    of rotRotate180: rotNone
    of rotCounterClockwise90: rotClockwise90
  of rotCounterClockwise90:
    case other
    of rotNone: rotCounterClockwise90
    of rotClockwise90: rotNone
    of rotRotate180: rotClockwise90
    of rotCounterClockwise90: rotRotate180
