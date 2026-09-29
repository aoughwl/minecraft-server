# Nimony compiler bugs found while porting a real codebase

This list was compiled while porting [an upstream open-source Rust Minecraft
server implementation](./NOTICE.md) (~2.3M lines across 20 crates) to
[Nimony](https://github.com/nim-lang/nimony), the from-scratch Nim
reimplementation this project targets. Every entry below is a bug hit doing
substantial, real-world Nimony development — a large codebase with real
variant types, generics, closures, and manual vtables (Nimony has no trait
objects) — not a synthetic test case written to find edge cases. Each was
minimally reproduced, root-caused as far as time allowed, and worked around
in this codebase; none of them block the *port* (workarounds exist for all),
but #1 blocks *runtime-verifying* most of it.

Ordered by severity/impact, most important first.

---

## 1. Closures-through-vtables crash at runtime — the single highest-impact bug found

**Severity: critical.** This is not a niche pattern: Nimony has no trait
objects, so this codebase's idiomatic replacement — a `ref object` holding a
handful of `proc(...) {.closure.}` fields, built once per concrete type and
dispatched through like a vtable — is used everywhere a Rust `dyn Trait` or
generic-over-a-trait was ported. That includes `Inventory`/`Slot`
(`src/inventory/`), `ScreenHandler` (`src/inventory/screenhandler.nim`),
`EntityBase` (`src/server/entity/entity.nim`), `BlockBehaviour`
(`src/server/block/blockbehaviour.nim`), `ItemBehaviour`
(`src/server/item/itembehaviour.nim`), and `CommandSource`/`ArgumentType`
(`src/command/`). **Confirmed independently at least 10 times** across
unrelated modules in this port.

**Failure mode:** `nimony check` passes clean every time. `nimony c -r`
(compile-and-run) crashes inside Nimony's own runtime panic machinery:

```
eraiser.nim(128,3) 'fnType.tagEnum == ParamsTagId' [AssertionDefect]
```

**Precise characterization (the important part):** this is *not* gated on
executing a closure call, or even on constructing a vtable instance. Evidence,
weakest to strongest claim:

- `src/server/entity/entitytest.nim`: constructs real `Entity`/`MarkerEntity`/
  `ExperienceOrbEntity` instances and calls through their `EntityBase`
  closures — crashes. (Expected.)
- `src/server/entity/concretetest.nim`: constructs plain `Entity`/
  `MarkerEntity`/`ExperienceOrbEntity` objects but **never calls through an
  `EntityBase` closure field at all** — still crashes. So the crash triggers
  on closure-*constructing* code merely being **reachable** in the compiled
  binary, not on it executing.
- `src/server/item/dyetest.nim`: imports `dye.nim`, which imports
  `entity.nim` for the `Player` type — **constructs no `EntityBase`, calls no
  closure, doesn't even reference the vtable type directly** — still crashes
  with the identical assertion. So it's sufficient for **any transitively
  imported module** (here, `entity.nim`, several `import`s away) to *define*
  closure-vtable-constructing code, even when the importing file's own code
  never touches it.
- `src/command/coordtest.nim`: importing `cmdsource.nim` for the
  `CommandSource` *type* alone triggers the crash, with **zero instances
  constructed and zero calls made**. This is the clearest evidence: the mere
  presence of the closure-vtable type, linked into the binary, is sufficient.

This is consistent with the bug living in closure-lifting/lowering at
whole-binary init or link time, not at any particular call site — which is
also why it's so easy to hit by accident and so hard to work around locally
(there is no local workaround; only "don't use closures-as-vtable-fields at
all," which isn't viable given Nimony has no other trait-object mechanism
yet).

**Impact:** everything built on the vtable pattern in this port — which is
most of the trait-object-shaped upstream code — currently only "checks," not
"runs." No local workaround exists; this needs a real compiler fix.

**Repro:** a `ref object` type with one or more `proc(...) {.closure.}`
fields, imported (not even instantiated) by another module, compiled with
`nimony c -r`. See `src/command/cmdsource.nim` (minimal type-only trigger) or
`src/server/entity/entity.nim` (full worked example with three levels of
transitivity documented in `src/server/entity/README.md`).

**Filed:** yes, via SendFeedback, before its quota ran out this session
(closure-assigned-without-`{.closure.}` variant, see #2). The *transitive
import* and *type-only, no-instance* refinements documented here are newer
findings from later in the session and were not separately filed (quota
exhausted) — worth filing as a follow-up, since they sharpen the bug
significantly.

---

## 2. Closure assigned to a `ref`-object proc-typed field without `{.closure.}` crashes `nimony check` itself

**Severity: high** (distinct from #1 — this one crashes at *check* time, not
just runtime, and has a slightly different signature).

**Failure mode:** assigning a closure to a `ref object` field typed as a
plain (non-`{.closure.}`) proc type crashes `nimony check` with:

```
contracts_fir.nim: AssertionDefect at isParamsTag
```

**Workaround:** always annotate vtable-style proc fields with `{.closure.}`
explicitly. Once that's done, `nimony check` passes (and you then hit bug #1
at runtime instead).

**Filed:** yes, via SendFeedback, early in this session.

---

## 3. `for x in someSeq: x(...)` over `seq[proc(...) {.closure.}]` crashes `nimony check`

**Severity: high.** A second, more precisely diagnosed variant of the
closure/vtable family, hit independently of #1/#2.

**Failure mode:** iterating a `seq[proc(...) {.closure.}]` field with
`for x in thatSeq: x(callArgs)` crashes `nimony check` (not just runtime)
with an internal AssertionDefect in `derefs.nim`'s
`checkForDangerousLocations`.

**Repro:** `src/command/cmdtree.nim`'s `meetsRequirements` originally wrote
`for req in node.requirements: ... req(source) ...` over a
`requirements*: seq[proc(source: CommandSource): bool {.closure.}]` field —
crashed. See the doc comment directly above `meetsRequirements` for the
exact citation.

**Workaround:** rewrite as an indexed `while` loop instead of `for...in`:

```nim
var i = 0
while i < node.requirements.len:
  if not node.requirements[i](source): return false
  inc i
```

**Filed:** yes, via SendFeedback, mid-session.

---

## 4. Self-recursive `ref T` field inside a `case` object of type `T` fails C-codegen despite passing `nimony check`

**Severity: medium-high.** Affects any Rust `enum` with a boxed
self-referential variant ported to a Nimony `case object` (a common shape:
e.g. a formula/expression tree where one variant wraps another instance of
the same type).

**Failure mode:** `nimony check` passes clean; the failure surfaces only at
C-codegen, as a destructor-type mismatch.

**Repro shape:**
```nim
type T = object
  case kind: SomeEnum
  of variantA: inner*: ref T
  of variantB: ...
```
Construct an instance populating the recursive variant, then run the *full*
compile (not just `check`).

**Where hit:** `src/server/entity/entity.nim`'s doc comment for
`CommandNode`/tree design explicitly calls this out as the reason command-
tree nodes reference each other by **index into an arena**, not by
`ref CommandNode` field — the design was changed specifically to avoid this
bug, not just to work around one instance of it. Also originally hit in
`src/server/enchantment/levelbasedvalue.nim`'s `Clamped`/`Fraction`/`Lookup`
variants (left semantically-checked-but-not-runtime-tested as a result).

**Workaround:** avoid the shape entirely — use an index into a flat array/
arena instead of a direct `ref T` self-reference inside a `case` variant.

**Filed:** yes, via SendFeedback, mid-session.

---

## 5. `seq[T].sort(closureComparator)` crashes C-codegen (not `nimony check`) when `T` is a plain object with an enum-typed field

**Severity: medium.** Another closure-adjacent C-codegen bug, distinct from
#1–#3 in trigger shape.

**Failure mode:** `.sort()` with a closure comparator on a `seq[T]` compiles
clean under `nimony check` but crashes at C-codegen when `T` is a plain
`object` with at least one enum-typed field. The identical pattern sorting a
`seq` of **tuples** elsewhere in this port works fine — the failure is
specific to the object+enum-field shape.

**Repro/found in:** `src/data_codegen/gen_game_rules.nim`'s
`manualSortByName` doc comment — bisected via the JSON keys that triggered
it.

**Workaround:** hand-written closure-free sort (e.g. insertion sort) instead
of `.sort()`, when `T` is an object with an enum field.

**Filed:** no — SendFeedback quota was exhausted by the time this was found;
documented in-repo only. Worth filing as a follow-up.

---

## 6. `std/json`'s `{}` lookup operator returns a default `JsonNode()` on a missing key, and using it (e.g. `.kind`) crashes at runtime

**Severity: medium** (data-generation-specific, but a real trap for anyone
using `std/json` for optional lookups).

**Failure mode:** `tree{"someKey"}` (or similar `{}`-shaped access) on a
missing key returns a default-constructed `JsonNode()` rather than
erroring or returning something recognizably absent. Calling `.kind` (or
nearly anything else) on that default value crashes at *runtime* with an
internal assertion failure. `nimony check` passes clean throughout —
only `nimony c -r` catches it.

**Minimal repro:** `var n = JsonNode(); discard n.kind` alone crashes.

**Found in:** `src/data_codegen/gen_noise_parameter.nim`'s port, while
handling an optional JSON key.

**Workaround/house fix:** `codegenutil.nim`'s `jsonTryGet(tree, key):
(bool, JsonNode)` — scans `pairs()` itself and never touches the broken
default. Adopted as the standard pattern for every subsequent data-codegen
generator in this port. A dedicated audit pass
(`src/data_codegen/README.md`, "Audit: JsonNode missing-key crash") checked
every existing generator in the suite for the risky `{}`/`{key}` accessor
and found the bug had never actually affected shipped output — every
generator already used `pairs()`-scanning independently, for the unrelated
reason that `JsonNode` also lacks a `[]` field-index operator.

**Filed:** no — quota exhausted; documented in-repo only.

---

## 7. `[T: SomeFloat]`-constrained generic proc can't resolve arithmetic operators (e.g. `-`) on its own type parameter `T`

**Severity: medium.** Affects any generic numeric helper meant to work over
both `float32` and `float64`.

**Failure mode:** `proc f[T: SomeFloat](a, b: T): T = a - b` (or similar
arithmetic) fails to resolve the operator on `T` inside the proc body,
despite the `SomeFloat` constraint. Reproduced standalone in a 2-line file
(exact repro not preserved verbatim, but trivially reconstructable from the
signature above).

**Found in:** `src/util/mathlerp.nim` (porting `lerp`/`lerp2`/`lerp3`/
`smoothstep` from upstream's single generic Rust implementation).

**Workaround:** duplicate the proc as concrete `float32`/`float64`
overloads instead of one generic.

**Filed:** yes, via SendFeedback, mid-session.

---

## 8. `const seq[T]` literals aren't always foldable at compile time

**Severity: low-medium** (routine annoyance, easy workaround, but hit
repeatedly enough across the codebase to be worth noting as a pattern).

**Failure mode:** `const testIds = @[3'u16, 5'u16, ...]` (or similar small
literal seqs, and separately, seqs with 1000+ entries built via computation)
can fail with `cannot evaluate expression at compile time`, even for
literals that look trivially foldable.

**Found in:** at least three independent places, including
`src/data_codegen/bitsettest.nim` (a 5-element literal) and multiple large
generated data tables (1000+ entries, e.g. `sound.nim`'s 1991-variant table).

**Workaround:** use `let` instead of `const` for the seq.

**Filed:** no — treated as a routine annoyance rather than filed
individually; worth a single consolidated filing if useful, since it
recurred often enough to suggest the const-folding heuristic is narrower
than expected for `seq` literals specifically.

---

## 9. `{.noinit.}` skips zero-initialization entirely, not just the "prove initialized" check

**Severity: low-medium** (a correctness trap, not a crash — arguably more
dangerous for that reason, since it produces silently wrong data rather than
failing loudly).

**Failure mode:** Nimony requires `{.noinit.}` on a proc/var that loop-fills
a fixed-size array/object element-by-element, to satisfy a "cannot prove
initialized" check. But `{.noinit.}` means exactly what it says — it skips
zero-initialization *entirely*, not just the compiler's proof requirement.
If a field is only set on *some* branches of the fill loop, it holds
uninitialized garbage memory on the branches that don't set it, not a zero
value.

**Found in:** `src/data_codegen/gen_dimension.nim` — `fixedTime` held
uninitialized garbage (`718871328032`) for `overworld.json`, which legitimately
has no `fixed_time` key, only caught because a round-trip test checked the
actual value rather than just "did it run."

**Workaround:** explicitly initialize (`result = SomeType()`) before the
fill loop whenever any field might not get written on every code path,
even with `{.noinit.}` present.

**Filed:** no — documented in-repo only.

---

## 10. Nesting a `readFile` call inside a `try` block that's itself inside a `walkDir`-iterating loop produces broken C-codegen

**Severity: low-medium** (narrow trigger shape, but silent — passes
`nimony check`, only fails at the C level).

**Failure mode:** calling two different `{.raises.}` procs (a `walkDir`
iterator and `readFile`) within the same `try` block — even indirectly,
where `walkDir`'s loop body calls `readFile` — produces broken C codegen
(`request for member ...` style C compile error), despite `nimony check`
passing clean.

**Found in:** `src/data_codegen/`, while writing a generator that walked a
JSON-file directory and read each file's contents in one pass.

**Workaround:** split into two passes — collect all file paths from
`walkDir` first (no `readFile` inside that loop), then `readFile` each
collected path in a separate loop/`try` block.

**Filed:** no — documented in-repo only.

---

## 11. `for (a, b) in someLocalSeqVar:` (tuple-destructuring over a `let`-bound local seq) crashes the parser

**Severity: low** (narrow, syntax-level, easy to route around).

**Failure mode:** `for (stem, path) in someLocalSeq:` where `someLocalSeq`
is a `let`-bound local `seq[(T, U)]` variable crashes the compiler with an
internal `[Bug]` parser assertion (`expected ')', but got: (let stem...)`).
The **identical syntax over a direct call expression** —
`for (stem, path) in listJsonStems(dir):` — works fine. The bug is specific
to destructuring over a pre-bound local variable, not the destructuring
syntax itself.

**Found in:** a `src/data_codegen/` generator, while refactoring a
directory-walk loop to reuse a precomputed stem/path list.

**Workaround:** iterate the seq by index and destructure manually, or keep
the iteration as a direct call expression rather than binding it to a local
first.

**Filed:** no — documented in-repo only.

---

## Summary table

| # | Bug | Nimony check | `c -r` / C-codegen | Filed |
|---|---|---|---|---|
| 1 | Closures-through-vtables (transitive import, type-only) | passes | crashes (`eraiser.nim`/`ParamsTagId`) | partially (base case only) |
| 2 | Closure→proc field without `{.closure.}` | crashes (`contracts_fir.nim`) | — | yes |
| 3 | `for x in seq[closure-proc]: x(...)` | crashes (`derefs.nim`) | — | yes |
| 4 | Self-recursive `ref T` in `case object T` | passes | crashes (C-codegen, destructor mismatch) | yes |
| 5 | `seq[T].sort(closure)`, T = object+enum field | passes | crashes (C-codegen) | no |
| 6 | `JsonNode{}` on missing key | passes | crashes (runtime assertion) | no |
| 7 | `[T: SomeFloat]` can't resolve arithmetic on `T` | crashes | — | yes |
| 8 | `const seq[T]` literals not always foldable | crashes | — | no |
| 9 | `{.noinit.}` skips zero-init, not just the proof | passes | silently wrong data | no |
| 10 | `readFile` inside `try` inside `walkDir` | passes | broken C-codegen | no |
| 11 | Tuple-destructure `for` over local seq var | crashes (parser) | — | no |
