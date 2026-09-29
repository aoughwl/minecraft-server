## A result that can be a complete success, or a partial/no result carrying
## an error message and a `Lifecycle`. Port of the core (non-macro) parts of
## pumpkingmc/crates/pumpkin-codecs/src/data_result.rs.
##
## Skipped: the `impl_apply!`-generated `apply2`..`applyN` family (applying
## an n-ary function across n `DataResult`s, short-circuiting to a combined
## error) - that's Rust macro-generated code taking `impl FnOnce` closures
## over a variadic type list; Nimony has neither variadic generics nor
## closures over a heterogeneous argument list, so there's no direct port.
## If callers need to combine two `DataResult`s once this framework is
## wired up, add a concrete `apply2[A, B, T](...)` proc by hand rather than
## trying to generalize.

import lifecycle

type
  DataResult*[R] = object
    case isSuccess*: bool
    of true:
      successResult*: R
      successLifecycle*: Lifecycle
    of false:
      partialResult*: seq[R] ## 0 or 1 elements standing in for `Option<R>`:
                              ## an unconstrained generic `R` has no default
                              ## value in Nimony (no zero-value trait), so a
                              ## `(bool, R)` tuple can't be constructed for the
                              ## "absent" case either - `seq[R]` needs no
                              ## default and empty/one-element reads exactly
                              ## like `Option`.
      errorLifecycle*: Lifecycle
      message*: string

proc lifecycleOf*[R](d: DataResult[R]): Lifecycle =
  if d.isSuccess: d.successLifecycle else: d.errorLifecycle

proc withLifecycle*[R](d: sink DataResult[R], newLifecycle: Lifecycle): DataResult[R] =
  result = d
  if result.isSuccess:
    result.successLifecycle = newLifecycle
  else:
    result.errorLifecycle = newLifecycle

proc addLifecycle*[R](d: sink DataResult[R], added: Lifecycle): DataResult[R] =
  withLifecycle(d, add(lifecycleOf(d), added))

proc newSuccessWithLifecycle*[R](value: sink R, lifecycle: Lifecycle): DataResult[R] =
  DataResult[R](isSuccess: true, successResult: value, successLifecycle: lifecycle)

proc newSuccess*[R](value: sink R): DataResult[R] =
  newSuccessWithLifecycle(value, experimental())

proc newErrorWithLifecycle*[R](message: string, lifecycle: Lifecycle): DataResult[R] =
  DataResult[R](isSuccess: false, partialResult: @[], errorLifecycle: lifecycle, message: message)

proc newError*[R](message: string): DataResult[R] =
  newErrorWithLifecycle[R](message, experimental())

proc newPartialErrorWithLifecycle*[R](message: string, partial: sink R, lifecycle: Lifecycle): DataResult[R] =
  DataResult[R](isSuccess: false, partialResult: @[partial], errorLifecycle: lifecycle, message: message)

proc newPartialError*[R](message: string, partial: sink R): DataResult[R] =
  newPartialErrorWithLifecycle(message, partial, experimental())

proc isError*[R](d: DataResult[R]): bool {.inline.} =
  not d.isSuccess

proc intoResult*[R](d: sink DataResult[R]): seq[R] =
  ## 0 or 1 elements in place of `Option<R>` - see the type doc comment.
  if d.isSuccess: @[d.successResult] else: @[]

proc intoResultOrPartial*[R](d: sink DataResult[R]): seq[R] =
  if d.isSuccess:
    @[d.successResult]
  else:
    d.partialResult
