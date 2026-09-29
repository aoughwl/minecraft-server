# Repo integrity audit

A verification/cleanup pass over the whole port, run after dozens of
concurrent porting forks had landed. Not a porting pass — checks that what
was reported as done is actually consistent, committed, and compiling.

## Scope

1. Every `import` in every `src/**/*.nim` file resolves to either a `std/`
   module, a cross-repo path covered by `nimony.paths`, or a file actually
   tracked in this repo (not just present on some agent's local disk).
2. `nimony check` run individually on all 347 `.nim` files under `src/`.
3. Spot-check of README claims (main `README.md` + each `src/*/README.md`)
   against the directories they describe.

## Findings

### 1. One missing committed file (found and fixed before this audit started)

`src/generated/noise_settings.nim` — the generator (`gen_noise_settings.nim`)
and its consumer (`world/flatgen.nim`) were committed, but the generated
output itself was left untracked. A fresh clone would have failed to build
`flatgen.nim`. Fixed in commit `4a3de5d` (already on `main` before this
audit ran) — confirmed both files `nimony check` clean with it present.

### 2. Import/tracking cross-reference: clean

Every non-stdlib import used in `src/` resolves to either a tracked file in
this repo or one of the three paths in `nimony.paths` (`../jwt/src`,
`../compress`, `../requests/nimony`). No other missing-file gaps found.

### 3. Full compile sweep: 347/347 clean

Ran `nimony check` on every tracked `.nim` file individually. One transient
failure was caught mid-sweep — `src/command/vec3arg.nim` failed because
`src/command/cmdsource.nim` had a duplicate `saveAllProc*` field declaration
(two concurrent forks both extended `CommandSource`'s manual vtable with a
field of that name around the same time). By the time this audit pulled
latest and re-checked, a later commit from another fork had already
resolved the collision — re-verified clean. No fix needed from this pass;
noting it because it's a real class of risk from this session's heavy
parallelism (many forks extending the same shared type), worth being aware
of if you see stray "attempt to redeclare" errors after a large parallel
batch — always re-pull and re-check before assuming a regression is real.

### 4. README-vs-reality: structurally consistent

File counts per `src/*` subdirectory match what the main `README.md`'s
porting-order table describes in scale and content. Not every subdirectory
has its own `README.md` (e.g. `src/auth/`, `src/util/`, `src/world/`,
`src/protocol/` don't) — those crates' status lives entirely in the main
`README.md` instead, which is consistent, not a gap.

### 5. Known, non-blocking observation: partial de-branding drift

The repo-wide de-branding pass (commit `79074d7`, mid-session) scrubbed all
"Pumpkin" references and renamed the local reference clone to
`upstream-ref`. Several later forks, working from task descriptions that
didn't always repeat that instruction, went back to citing real upstream
Rust identifiers when describing what a file ports from or depends on (e.g.
`pumpkin_util::version`, `pumpkin_protocol::codec::recipe`,
`#[pumpkin_block]`, `pumpkin-plugin-wit`). These are literal, factual
references to the actual upstream crate's module/macro names in doc
comments explaining provenance or a dependency gap — not marketing
branding — but they are inconsistent with the earlier pass's "always say
'upstream' generically" convention. Left undone by this audit (a real fix
here means judgment-call editing of prose across a dozen files, out of
scope for an integrity pass); flagging for whoever next touches those
files, or for a dedicated follow-up sweep if strict consistency matters.

## Not covered by this audit

- Runtime behavior (`nimony c -r`) beyond what NIMONY-COMPILER-BUGS.md
  already documents — this pass only re-ran `nimony check`, which is a much
  weaker guarantee for anything hitting the closures-through-vtables bug.
- Correctness of ported logic against upstream semantics (each fork's own
  report is the source of truth for what was verified and how).
