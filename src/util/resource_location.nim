## Port of pumpkingmc/crates/pumpkin-util/src/resource_location.rs
##
## Rust's `ToResourceLocation`/`FromResourceLocation` are traits any type can
## implement. Nimony has no trait-object dispatch worth reaching for here
## (see nim-vs-nimony: "Macros replaced by compiler plugins ... multi-methods
## removed"), so these are left as plain proc *signatures* documented per
## type, ported the same way the rest of this codebase ports a Rust trait
## with exactly one meaningful shape: implementers just define a proc named
## `toResourceLocation`/`fromResourceLocation` for their own type; there is
## no shared dispatch to model.

type
  ResourceLocation* = string
    ## A fully qualified identifier for resources, usually in
    ## `namespace:path` form.
