# aowlmony compiler bugs found while porting a real codebase

This list was compiled while porting [an upstream open-source Rust Minecraft
server implementation](./NOTICE.md) (~2.3M lines across 20 crates) to
aowlmony, the compiler this project targets. Every entry below is a bug hit doing
substantial, real-world aowlmony development — a large codebase with real
variant types, generics, closures, and manual vtables (aowlmony has no trait
objects) — not a synthetic test case written to find edge cases. Each was
minimally reproduced, root-caused as far as time allowed, and worked around
in this codebase; none of them block the *port* (workarounds exist for all),
but #1 blocks *runtime-verifying* most of it.

Ordered by severity/impact, most important first.

---

## 1. Closures-through-vtables crash at runtime — the single highest-impact bug found

**Severity: critical.** This is not a niche pattern: aowlmony has no trait
objects, so this codebase's idiomatic replacement — a `ref object` holding a
handful of `proc(...) {.closure.}` fields, built once per concrete type and
dispatched through like a vtable — is used everywhere a Rust `dyn Trait` or
generic-over-a-trait was ported. That includes `Inventory`/`Slot`
(`src/inventory/`), `ScreenHandler` (`src/inventory/screenhandler.aowl`),
`EntityBase` (`src/server/entity/entity.aowl`), `BlockBehaviour`
(`src/server/block/blockbehaviour.aowl`), `ItemBehaviour`
(`src/server/item/itembehaviour.aowl`), and `CommandSource`/`ArgumentType`
(`src/command/`). **Confirmed independently at least 10 times** across
unrelated modules in this port.

**Failure mode:** `aowlmony check` passes clean every time. `aowlmony c -r`
(compile-and-run) crashes inside aowlmony's own runtime panic machinery:

```
eraiser.aowl(128,3) 'fnType.tagEnum == ParamsTagId' [AssertionDefect]
```

**Precise characterization (the important part):** this is *not* gated on
executing a closure call, or even on constructing a vtable instance. Evidence,
weakest to strongest claim:

- `src/server/entity/entitytest.aowl`: constructs real `Entity`/`MarkerEntity`/
  `ExperienceOrbEntity` instances and calls through their `EntityBase`
  closures — crashes. (Expected.)
- `src/server/entity/concretetest.aowl`: constructs plain `Entity`/
  `MarkerEntity`/`ExperienceOrbEntity` objects but **never calls through an
  `EntityBase` closure field at all** — still crashes. So the crash triggers
  on closure-*constructing* code merely being **reachable** in the compiled
  binary, not on it executing.
- `src/server/item/dyetest.aowl`: imports `dye.aowl`, which imports
  `entity.aowl` for the `Player` type — **constructs no `EntityBase`, calls no
  closure, doesn't even reference the vtable type directly** — still crashes
  with the identical assertion. So it's sufficient for **any transitively
  imported module** (here, `entity.aowl`, several `import`s away) to *define*
  closure-vtable-constructing code, even when the importing file's own code
  never touches it.
- `src/command/coordtest.aowl`: importing `cmdsource.aowl` for the
  `CommandSource` *type* alone triggers the crash, with **zero instances
  constructed and zero calls made**. This is the clearest evidence: the mere
  presence of the closure-vtable type, linked into the binary, is sufficient.

This is consistent with the bug living in closure-lifting/lowering at
whole-binary init or link time, not at any particular call site — which is
also why it's so easy to hit by accident and so hard to work around locally
(there is no local workaround; only "don't use closures-as-vtable-fields at
all," which isn't viable given aowlmony has no other trait-object mechanism
yet).

**Impact:** everything built on the vtable pattern in this port — which is
most of the trait-object-shaped upstream code — currently only "checks," not
"runs." No local workaround exists; this needs a real compiler fix.

**Repro:** a `ref object` type with one or more `proc(...) {.closure.}`
fields, imported (not even instantiated) by another module, compiled with
`aowlmony c -r`. See `src/command/cmdsource.aowl` (minimal type-only trigger) or
`src/server/entity/entity.aowl` (full worked example with three levels of
transitivity documented in `src/server/entity/README.md`).

**Filed:** yes, via SendFeedback, before its quota ran out this session
(closure-assigned-without-`{.closure.}` variant, see #2). The *transitive
import* and *type-only, no-instance* refinements documented here are newer
findings from later in the session and were not separately filed (quota
exhausted) — worth filing as a follow-up, since they sharpen the bug
significantly.

**Further refinement — not specific to `entity.aowl`:** `src/server/command/setidletimeout.aowl`
(a command file that imports neither `entity.aowl` nor `cmdsource.aowl`'s
`player` field's type) hits the exact same signature. The actual trigger is
`src/command/cmdtree.aowl`/`cmddispatch.aowl`'s own `Command`/`Requirement`
closure-typed fields — anything importing the command tree/dispatcher
infrastructure at all inherits the crash, independent of `entity.aowl`. So
the blast radius is broader than "everything touching Entity": it's
"everything touching *any* closure-vtable type", which in this port means
most of `src/command/`, `src/inventory/`'s screen handlers, `src/server/block/`,
`src/server/item/`, and `src/server/entity/` alike. See
`src/server/command/setidletimeouttest.aowl` for the confirming repro.

---

## 2. Closure assigned to a `ref`-object proc-typed field without `{.closure.}` crashes `aowlmony check` itself

**Severity: high** (distinct from #1 — this one crashes at *check* time, not
just runtime, and has a slightly different signature).

**Failure mode:** assigning a closure to a `ref object` field typed as a
plain (non-`{.closure.}`) proc type crashes `aowlmony check` with:

```
contracts_fir.aowl: AssertionDefect at isParamsTag
```

**Workaround:** always annotate vtable-style proc fields with `{.closure.}`
explicitly. Once that's done, `aowlmony check` passes (and you then hit bug #1
at runtime instead).

**Filed:** yes, via SendFeedback, early in this session.

---

## 3. `for x in someSeq: x(...)` over `seq[proc(...) {.closure.}]` crashes `aowlmony check`

**Severity: high.** A second, more precisely diagnosed variant of the
closure/vtable family, hit independently of #1/#2.

**Failure mode:** iterating a `seq[proc(...) {.closure.}]` field with
`for x in thatSeq: x(callArgs)` crashes `aowlmony check` (not just runtime)
with an internal AssertionDefect in `derefs.aowl`'s
`checkForDangerousLocations`.

**Repro:** `src/command/cmdtree.aowl`'s `meetsRequirements` originally wrote
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

## 4. Self-recursive `ref T` field inside a `case` object of type `T` fails C-codegen despite passing `aowlmony check`

**Severity: medium-high.** Affects any Rust `enum` with a boxed
self-referential variant ported to a aowlmony `case object` (a common shape:
e.g. a formula/expression tree where one variant wraps another instance of
the same type).

**Failure mode:** `aowlmony check` passes clean; the failure surfaces only at
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

**Where hit:** `src/server/entity/entity.aowl`'s doc comment for
`CommandNode`/tree design explicitly calls this out as the reason command-
tree nodes reference each other by **index into an arena**, not by
`ref CommandNode` field — the design was changed specifically to avoid this
bug, not just to work around one instance of it. Also originally hit in
`src/server/enchantment/levelbasedvalue.aowl`'s `Clamped`/`Fraction`/`Lookup`
variants (left semantically-checked-but-not-runtime-tested as a result).

**Workaround:** avoid the shape entirely — use an index into a flat array/
arena instead of a direct `ref T` self-reference inside a `case` variant.

**Filed:** yes, via SendFeedback, mid-session.

---

## 5. `seq[T].sort(closureComparator)` crashes C-codegen (not `aowlmony check`) when `T` is a plain object with an enum-typed field

**Severity: medium.** Another closure-adjacent C-codegen bug, distinct from
#1–#3 in trigger shape.

**Failure mode:** `.sort()` with a closure comparator on a `seq[T]` compiles
clean under `aowlmony check` but crashes at C-codegen when `T` is a plain
`object` with at least one enum-typed field. The identical pattern sorting a
`seq` of **tuples** elsewhere in this port works fine — the failure is
specific to the object+enum-field shape.

**Repro/found in:** `src/data_codegen/gen_game_rules.aowl`'s
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
internal assertion failure. `aowlmony check` passes clean throughout —
only `aowlmony c -r` catches it.

**Minimal repro:** `var n = JsonNode(); discard n.kind` alone crashes.

**Found in:** `src/data_codegen/gen_noise_parameter.aowl`'s port, while
handling an optional JSON key.

**Workaround/house fix:** `codegenutil.aowl`'s `jsonTryGet(tree, key):
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

**Found in:** `src/util/mathlerp.aowl` (porting `lerp`/`lerp2`/`lerp3`/
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
`src/data_codegen/bitsettest.aowl` (a 5-element literal) and multiple large
generated data tables (1000+ entries, e.g. `sound.aowl`'s 1991-variant table).

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

**Failure mode:** aowlmony requires `{.noinit.}` on a proc/var that loop-fills
a fixed-size array/object element-by-element, to satisfy a "cannot prove
initialized" check. But `{.noinit.}` means exactly what it says — it skips
zero-initialization *entirely*, not just the compiler's proof requirement.
If a field is only set on *some* branches of the fill loop, it holds
uninitialized garbage memory on the branches that don't set it, not a zero
value.

**Found in:** `src/data_codegen/gen_dimension.aowl` — `fixedTime` held
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
`aowlmony check`, only fails at the C level).

**Failure mode:** calling two different `{.raises.}` procs (a `walkDir`
iterator and `readFile`) within the same `try` block — even indirectly,
where `walkDir`'s loop body calls `readFile` — produces broken C codegen
(`request for member ...` style C compile error), despite `aowlmony check`
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

## 12. `var Table[K, V]` out-parameter writes are lost across the proc-call boundary on return

**Severity: high.** This is a silent-data-loss bug, not a crash — the kind
that's easy to ship undetected. A proc taking `results: var Table[K, V]` and
writing into it (`results[key] = value`) behaves correctly *while still
inside that proc* — `results.len` was observed growing normally on every
write, from 1 up past 30 in an instrumented run — but once the proc returns,
the caller's own table reflects only the very first write. Over 99% of
~1500 real entries vanished silently, with no error at any stage: `aowlmony
check` passed, `aowlmony c -r` ran to completion and printed a plausible
(wrong) result.

**Reproduced independent of recursion depth**: the first attempt threaded
`var Table` through a recursive directory-walk proc (hypothesizing the loss
was recursion-depth-related, since deeper writes seemed to vanish first);
rewriting the *same* walk iteratively — a single proc, one `while` loop, no
recursion at all — hit the identical loss pattern. The bug is in `var
Table[K, V]` parameter passing itself, not in recursion.

**Found in:** `src/data_codegen/gen_template_bytes.aowl`/`gen_test_instance.aowl`
while porting `template_bytes.rs`/`test_instance.rs` (a directory-walk +
lookup-table generator pair).

**Workaround:** have the callee return its findings by value (`seq[T]`, in
this case) instead of writing into a `var Table`/`var seq`-as-accumulator
out-parameter; have the caller build its own table from what's returned.
Every write then happens in the caller's own frame.

**Filed:** no — documented in-repo only.

---

## 13. Two `{.closure.}` procs in the same object-constructor call, both capturing the same local `var`/`ref`, break the "prove initialized" check for that variable afterward

**Severity: low-medium** (a real diagnostic-quality bug — the compiler wrongly
rejects working code with a confusing error, rather than crashing or
miscompiling).

```nim
var current = Peaceful
let source = CommandSource(
  difficultyProc: proc(): Difficulty {.closure.} = current,
  setDifficultyProc: proc(d: Difficulty) {.closure.} = current = d,
)
echo current  # Error: cannot prove that `current` has been initialized
```

Each closure alone captures `current` fine (`aowlmony check` passes with just
one closure in the constructor). Adding the *second* closure that also
captures it — even though both closures obviously see the same already-
initialized variable — makes any use of `current` *after* the constructor
call fail to prove initialization. Reproduced identically whether `current`
is a plain `var Difficulty` or a `ref object` field access
(`box.current`/`box.setTo`), so it's not specific to value vs. reference
types.

**Found in:** `src/server/command/difficultytest.aowl`, testing `/difficulty`'s
query+set closures sharing one `CommandSource`.

**Workaround:** don't have two inline closures in the same constructor
capture-and-mutate the same local. Use a single global `var` + a top-level
named `{.closure.}` proc instead (the closure no longer needs to *capture*
anything, since it reads/writes the global directly), or split the mutation
across separately-constructed sources so no two closures alias one variable.

**Filed:** no — documented in-repo only (SendFeedback quota exhausted this
session).

---

## 14. Auto-generated `=dup`/`=destroy` hook for `ref object` segfaults on a nil receiver

Reproduced against the *updated* `~/aowlmony/bin` toolchain (the one with
fixes #1's three layers already applied — this is a different, newer bug
uncovered only once #1 stopped masking it). `src/server/entity/entity.aowl`
+ `entitytest.aowl` now compile and **link** clean (no more C-codegen
errors at all), but the produced `entitytest.exe` segfaults immediately on
start (`STATUS_ACCESS_VIOLATION`, exit `-1073741819`).

**Repro:** `aowlmony c -r src\server\entity\entitytest.aowl` (PowerShell), or
run the built `entitytest.exe` directly under gdb:

```
gdb -batch -ex run -ex bt -ex "info registers" --args nimcache\...\entitytest.exe
```

Crash is in a compiler-generated closure named
`X60Qanonproc_0_entv11w8h1`, which is the `=destroy`/`=dup` pair for
`ref Entity` (symbol names `eQdestroyQ_Aref...Entity...` /
`eQdupQ_Aref...Entity...` visible in the disassembly right after it).
Disassembly of the crashing function:

```
push   %rbx
sub    $0x20,%rsp
mov    %rcx,%rbx        ; rbx = self (the ref Entity being dup'd)
mov    $0x0,%ecx
call   =destroy(Entity)
mov    0x10(%rbx),%rcx  ; <-- CRASHES HERE: rbx == 0
call   =dup(Entity)
```

At the crash, `rbx` (the generic register alias used for `self` across
this call) is `0x0`. The generated hook body unconditionally dereferences
the receiver at offset `0x10` to fetch a field to pass into the next hook
call, with **no nil-check first**. Any `ref object` value that legitimately
holds `nil` (here: `EntityBase.vehicle*: nil EntityBase`, or any nil
`EntityBase`/`Entity` ref flowing through a sink/copy path during object
construction) triggers this the moment the compiler's own dup/destroy
plumbing touches it — it's not app-level misuse, the generated hook itself
is missing the standard `if self != nil:` guard that hand-written
`=destroy`/`=dup` procs always have.

**Workaround applied in this port:** none yet at the app level — the
crash is inside compiler-generated code, not anything `entity.aowl` calls
directly, so there's no source-level pattern to avoid short of not using
`ref object` fields that can hold `nil` at all (not viable here; `vehicle`
legitimately has no value most of the time). Left failing; `entitytest.aowl`
is understood to compile+link correctly but not run correctly until this
is fixed upstream. Next step if picked back up: patch the hook-emission
site in hexer (wherever it synthesizes `=dup`/`=destroy` bodies for `ref
object` types) to emit `if self.isNil: return` (or equivalent) before the
field-access/dispatch call, mirroring what hand-written hooks already do.

**Filed:** no — found at the very end of this session, after the #1 fix
verification pass; not yet reported upstream.

---

## 15. `import std/strutils` crashes nifler on `std/parseutils.aowl` — FIXED

**Status: fixed**, `~/aowlmony/bin/nifler.exe` rebuilt and redeployed.

Discovered while building `src/main.aowl` (the new network entrypoint).
Bare `import std/strutils` - nothing else, no app code - crashed
`nifler.exe` while parsing the stdlib's own `std/parseutils.aowl`
(strutils imports it):

```
Error: unhandled exception: bridge.aowl(265, 5) `allowEmpty` unexpected
nkEmpty in parent nkStmtListExpr at 246:24 [AssertionDefect]
FAILURE: nifler.exe --portablePaths --deps parse
  ...\aowlmony\lib\std\parseutils.aowl nimcache\....p.nif
```

**Root cause, confirmed (not the #1-fix commits):** `git diff --stat` of
commits `349da94a`/`f73e7361`/`369e0758` against their parent shows they
touch only `src/hexer/` and `src/lambdalifting` - never `src/nifler/` or
`src/lib/`. Ruled out as the cause directly. The real bug is a
pre-existing, long-standing gap in `src/nifler/bridge.aowl`'s
`nkStmtListType, nkStmtListExpr` branch (around line 453): every other
statement-list-shaped branch in that file passes `allowEmpty = true`
when recursing over child statements (7 other call sites do), but this
one branch didn't, so a `when`/conditional-compilation gap or any other
construct in `std/parseutils.aowl` that legitimately produces an empty
statement node inside a statement-list-*expression* tripped the
`assert allowEmpty` check. It happened to surface only now because this
was the first time this session's rebuilt toolchain's nifler was pointed
at `std/parseutils.aowl` with a matching/current `lib/`.

**Fix:** added `allowEmpty = true` to both `toNif` calls in that branch
in `~/aowlmony-fix-worktree/src/nifler/bridge.aowl`, matching the pattern
used everywhere else in the file. Rebuilt `nifler.exe` **from PowerShell**
(building via the Bash tool silently produced a stale binary due to the
known gcc/Git-Bash swallowed-error gotcha - `gcc` run standalone on the
failing translation unit succeeded, proving the Bash-reported failure was
spurious), copied to `~/aowlmony/bin/nifler.exe`.

**Verified:**
- `import std/[strutils, syncio]; echo "hi".toUpperAscii()` now compiles
  and runs, printing `HI` (exit 0).
- `src/server/entity/entitytest.aowl` (bug #1's original repro) still
  compiles and links clean, failing only at the separate, already-known
  bug #14 runtime crash - confirming this fix didn't reintroduce or
  interact with the #1 closures-through-vtables fix.

No other files in this port have been re-verified against the fixed
toolchain yet; anything that depends on `strutils` transitively should
now work again but hasn't been swept.

---

## Summary table

| # | Bug | aowlmony check | `c -r` / C-codegen | Filed |
|---|---|---|---|---|
| 1 | Closures-through-vtables (transitive import, type-only) | passes | crashes (`eraiser.aowl`/`ParamsTagId`) | partially (base case only) |
| 2 | Closure→proc field without `{.closure.}` | crashes (`contracts_fir.aowl`) | — | yes |
| 3 | `for x in seq[closure-proc]: x(...)` | crashes (`derefs.aowl`) | — | yes |
| 4 | Self-recursive `ref T` in `case object T` | passes | crashes (C-codegen, destructor mismatch) | yes |
| 5 | `seq[T].sort(closure)`, T = object+enum field | passes | crashes (C-codegen) | no |
| 6 | `JsonNode{}` on missing key | passes | crashes (runtime assertion) | no |
| 7 | `[T: SomeFloat]` can't resolve arithmetic on `T` | crashes | — | yes |
| 8 | `const seq[T]` literals not always foldable | crashes | — | no |
| 9 | `{.noinit.}` skips zero-init, not just the proof | passes | silently wrong data | no |
| 10 | `readFile` inside `try` inside `walkDir` | passes | broken C-codegen | no |
| 11 | Tuple-destructure `for` over local seq var | crashes (parser) | — | no |
| 12 | `var Table[K,V]` out-param writes lost on return | passes | **silently wrong data, no crash** | no |
| 13 | Two closures in one constructor sharing a captured var breaks init-proof | crashes (false diagnostic) | — | no |
| 14 | Auto `=dup`/`=destroy` hook for `ref object` derefs nil receiver, no guard | passes, links | segfault at runtime (`entitytest.exe`) | no |
| 15 | `import std/strutils` crashes nifler on `std/parseutils.aowl` - **REGRESSION** from this session's #1 fix rebuild | crashes (parse) | — | no |

---

## Status, 2026-11-08

Bug 1 above, closures through vtables, is fixed in aowlhexer. It was not one crash but three separate lowering bugs:
two closure fields in one constructor evaluated out of order (the second moved the shared environment before the
first duplicated it), a closure field called from a module declaring no closures of its own was left as a call on a
tuple, and a field key spelled like a captured local was rewritten as a capture.

Still open: a closure inside a returned named tuple (`proc f(): tuple[a: int, b: proc(): int {.closure.}]`) stops
the hexer with `expected ')'`. Return an object instead.

Also open, found 2026-11-09: **#16, reading a closure field from a local object variable frees the closure.** Given
`let n = s[0]` or `var n = s[0]` where the element is a value object with a closure field, both `n.f()` and `let g = n.f`
drop one reference on the environment without having taken one. A few calls later the environment is freed, the next call
runs on freed memory, and mimalloc aborts with 0xC0000409. This was the `/setblock` crash. Reads through `s[0].f`, through a
`ref` (`n.r.f`) or a by-value parameter are fine, and so is copying the object without reading the closure. Workaround:
do not bind the element to a local; write `s[i].f()`. Repro; prints a value from 0xdfdf... rather than 2:

```nim
type
  Fn = proc(): int {.closure.}
  B = object
    s: string
    f: Fn
proc mk(x: int): Fn =
  result = proc(): int {.closure.} = x + 1
proc use(s: seq[B]) =
  let n = s[0]
  discard n.f()
proc main =
  let s = @[B(s: "x", f: mk(1))]
  for k in 0..<10:
    use(s)
    var junk: seq[string] = @[]
    for q in 0..<50:
      junk.add("xxxxxxxxxxxxxxxxxxxxxxxxx" & $q)
  echo s[0].f()
main()
```

## `withEntity(source, entity)` fails type inference in savelistkilltest

`src/server/command/savelistkilltest.aowl` (the `/kill` block) fails with
`Type mismatch at [position]` at the call `withEntity(source, entity)`, although `withEntity`
takes a CommandSource and a CommandEntity and both arguments have those types. Binding the
call to a name does not help (an earlier note here claimed it did; that was wrong). The test now
no longer builds a source with an entity: `newCommandSource(..., entity, ...)` fails the same way, so the self-kill case is not covered there. Cause not isolated (suspect the `entity` value or its closure fields).

## `case` over distinct integer constants passes `check` but fails in gcc

`case id of blockIdX:` where the labels are `const X = BlockId(n)` (a distinct type) type-checks, then
gcc rejects the emitted C with "case label does not reduce to an integer constant". Hit by several
block files (cauldron, coral); worked around with if-chains. `check` does not catch it.

## hexer assertion failures that broke `server/entity`, `server/command` (clone/data) and `server/net/java` tests

At HEAD these tests failed in `nifmake` at `hexer c <module>.s.nif` ("[Assertion Failure]", "body must consume all children",
"could not find symbol: vtableTemp.1", "could not find symbol: make.0") or at the C link (see below). Each failing module was
shrunk to a repro with a source-level delta reduction (one module at a time, `hexer c` run on its `.s.nif`). The root causes, all
in the hexer phase (they pass `check`/nimsem), and the workaround used in the port:

1. **A call of an imported global closure variable.** `var gHook*: proc(x: int) {.closure.}` in module A, `gHook(1)` in module B,
   asserts in hexer for B (a same-module call, a non-closure proc type and `let h = gHook; h(1)` are fine). 84 call sites
   (the plugin event hooks of commit 1b8573a, `gDropStack`, `gFromType`, `gSetCommandBlockHook`, ...) were hit. Workaround:
   every `var gName*: proc(...)` now has an exported wrapper `callName(...)` right after it (a same-module call), and importers
   call the wrapper. The `writePacketFor` template in `net/java/javamod.aowl` binds `gPacketSentHook` to a local first.
2. **A closure call with a temporary argument.** `let f = b.prepareImpl; f(PrepareArgs(...))`, `gDropItemHook(ownerOf(self), item)`,
   `gDropStack(w, pos, newItemStack(...))` and `f($category & ":" & $stat, n)` assert ("body must consume all children").
   Workaround: bind the argument to a `let` first (`blockbehaviour.aowl` x5, `player.aowl`, `entitymod.aowl`, `blockprelude.aowl`),
   and call a closure field directly (`b.prepareImpl(args)`) rather than through a local copy.
3. **A downcast of a call result.** `BellBlockEntity(t1.unsafeGet)`, `T(e)` inside `some(...)` and `x.unsafeGet.field = v` on an
   `Option[ref]` give "could not find symbol: vtableTemp.1". Workaround: bind the value to a local first (`asType` in
   `blockprelude.aowl`, `crafter`, `dispenser`, `dropper`, `comparator`).
4. **A closure local declared in a loop over `stacks[i]`.** `let item = stacks[i].item; let isTagged = proc ... item ...` inside
   `applyFunction`'s loop (src/server/world/loot.aowl) gives "could not compute type of: (dot (hderef (call [] ...". Moved into
   its own proc `smeltStack`.
5. **A closure that calls its captured closure parameter plus another closure local** (`newScreenFactory`,
   src/server/block/containers.aowl) gives "could not find symbol: make.0" / an assertion. The body is a plain proc
   `makeScreenHandler(make, syncId, player)` that the closure calls.

Not fixed: `src/server/block/blocks/bed.aowl` still asserts ("body must consume all children") and the entity and `net/java` test
chains import it. The shrinker kept `bedBlockNormalUse_BlockBehaviour` plus most of the file; stubbing any one of several procs
makes it go away, so the trigger is not a single construct (possibly the number of closure locals in one proc). Other modules
may surface once this one is passed.

Source bugs found on the way: `resourcePackResponseMessage` in net/java/config.aowl named a parameter `result`, shadowing the
implicit result (renamed `response`); `configtest.aowl` used `echo` without importing `std/syncio`; `clonetest` no longer keeps
a `run` closure over the dispatcher (the Aref[CommandDispatcher] destructor C error in item 1's family: the destructor call
emitted in the test module passes the pointee by value instead of its address; the module does not reach C for any test that
drops its local dispatcher, none of which was verified here beyond clonetest).
