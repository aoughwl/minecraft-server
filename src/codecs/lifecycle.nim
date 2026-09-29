## A marker to convey the lifecycle of some object: stable, experimental, or
## deprecated. Port of pumpkingmc/crates/pumpkin-codecs/src/lifecycle.rs

type
  LifecycleKind* = enum
    lkStable
    lkExperimental
    lkDeprecated

  Lifecycle* = object
    case kind*: LifecycleKind
    of lkDeprecated:
      deprecatedSince*: uint32 ## Date from which it was marked deprecated;
                               ## lower means deprecated earlier.
    else:
      discard

proc stable*(): Lifecycle {.inline.} = Lifecycle(kind: lkStable)
proc experimental*(): Lifecycle {.inline.} = Lifecycle(kind: lkExperimental)
proc deprecated*(since: uint32): Lifecycle {.inline.} =
  Lifecycle(kind: lkDeprecated, deprecatedSince: since)

proc add*(a, b: Lifecycle): Lifecycle =
  ## Combines two lifecycles, returning the more restrictive of the two:
  ## experimental beats everything; between two deprecations the
  ## earlier-deprecated one wins; a lone deprecation beats stable.
  if a.kind == lkExperimental or b.kind == lkExperimental:
    return experimental()
  if a.kind == lkDeprecated and b.kind == lkDeprecated:
    return if a.deprecatedSince < b.deprecatedSince: a else: b
  if a.kind == lkDeprecated:
    return a
  if b.kind == lkDeprecated:
    return b
  stable()
