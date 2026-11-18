# Plugin jobs (worker threads for plugins)

A plugin can hand pure computation to the server's worker threads and get the answer back on the tick thread. This is phase 6 of
`docs/MULTITHREADING.md`; the primitive is `src/server/sim/plugjob.aowl`, the plugin glue is `src/plugin/engine/enginejobs.aowl`.

## What a job is

Plugins are programs the engine runs, and the engine may only be called from the thread that started it. Plugin code therefore **never runs on
a worker**. A job names a **kernel** the server provides, plus an input string; the worker runs the kernel on those bytes and nothing else.

| kind | input | `value` | `text` |
|---|---|---|---|
| `fnv1a` | any bytes | the 32-bit FNV-1a hash | the hash in decimal |
| `primes` | decimal `n` (at most 20,000,000) | how many primes are <= n | the same, in decimal |
| `sort` | whitespace-separated integers (first 8192 used) | how many numbers | the numbers sorted, space separated |

Input is limited to 64 KiB. The kernels are the server's, so the rules for a job body (no world, entity, `setBlockState`, hook, host call) are
kept by construction; a new kernel added to `enginejobs.aowl` must keep them (raw memory only, no tick-owned state). Under `MC_THREAD_ASSERT=1`
`ownerguard` records a violation if a kernel reaches tick-owned code.

## Host ABI (version 1)

Host calls, the same mechanism as every other plugin call (`hostv("name", args...)` in JavaScript, the SDK in aowlmony):

| call | answer |
|---|---|
| `job_abi_version()` | `1`. Feature-test with it; it grows when a call or an event field changes meaning. Adding a kernel does not change it. |
| `job_submit(kind, input)` | job id > 0, `-1` unknown kind, `-2` input over 64 KiB |
| `job_status(id)` | `0` pending, `1` finished but not yet delivered, `2` failed (kernel raised), `-1` unknown or already delivered |
| `job_pending()` | how many of the plugin's jobs are not yet delivered |

Delivery is the plugin's entry **`on_job`** (listed in the entry names, subscribed by the SDK when you submit): `event_num("id")`,
`event_num("value")`, `event_num("failed")` (0 or 1), `event_str("text")`.

Guarantees (tested in `enginejobstest.aowl`, at 1 and 4 threads):

* the answer is delivered **only** in the tick's poll (`tickPluginManager` calls `tickEngineJobs` once per tick, on the tick thread), never from a
  worker and never inside `job_submit`, in every thread mode;
* a plugin's jobs are delivered **in submission order**, even when a later job finishes first;
* the `on_job` handler runs on the tick thread: it may touch the world, players and hooks;
* unloading a plugin waits (at most about 5 seconds) for its running jobs and drops their answers; server stop does the same for all
  (`stopPluginManager`), then joins the workers.

## SDK

JavaScript (`plugin_sdk/pluginsdk.js`):

```js
var id = job("primes", "100000", function (r) { server.broadcast("primes: " + r.value); });   // r = { id, value, failed, text }
jobStatus(id);           // 0 pending, 1 done, 2 failed, -1 unknown/delivered
jobAbiVersion();         // 1
```

aowlmony (`plugin_sdk/pluginsdk.aowl`):

```nim
let id = runJob("sort", "5 3 9", proc (r: JobResult) {.nimcall.} = log("sorted " & r.text))
```

A handler is a plain procedure (`nimcall`), like the task handlers. All JavaScript plugins share one program and one job owner; a JavaScript
plugin's `on_job` handler is picked by job id, so two plugins never see each other's answers. `examples/jobs-js` is a small plugin (`/jobdemo`).

## Threads

By default the job set is **inline** (one thread): the kernel runs inside `job_submit` and its answer still waits for the next poll, so plugins
behave the same with and without workers. `MC_PLUGIN_JOBS=1` gives the jobs the workers of the resolved thread plan (`MC_THREADS`, same rules as
`docs/MULTITHREADING.md` section 5). `jobpool` has one live worker pool per process: enabling plugin job workers together with another pool that
has workers (path jobs, net encode) is not supported until the pools are shared.
