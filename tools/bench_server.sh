#!/bin/sh
# Runs tools/bench_server.py over the configuration matrix of docs/MULTITHREADING.md "Measured on a real server", round-robin
# (config A, B, C ... then again) so that machine drift hits every config alike.
#   sh tools/bench_server.sh <server exe> [rounds=3]       BENCH_PORT=26010 BENCH_RESULTS=<jsonl> (default ../bench_results.jsonl)
# Do not run other heavy jobs at the same time; the script records the machine CPU percentage and the number of build processes per run.
EXE="$1"; ROUNDS="${2:-3}"
[ -f "$EXE" ] || { echo "usage: bench_server.sh <server exe> [rounds]"; exit 2; }
HERE="$(cd "$(dirname "$0")" && pwd)"
export BENCH_RESULTS="${BENCH_RESULTS:-$HERE/../../bench_results.jsonl}"
r=1
while [ $r -le $ROUNDS ]; do
  while read -r label envs; do
    [ -z "$label" ] && continue
    echo "round $r: $label $envs"
    python "$HERE/bench_server.py" "$EXE" "$label" $envs > /dev/null < /dev/null
  done <<'CFG'
base MC_CHUNK_WORKERS=0
cw4 MC_CHUNK_WORKERS=4
cw8 MC_CHUNK_WORKERS=8
thr_auto MC_THREADS=0
thr1 MC_THREADS=1
cw4_save MC_CHUNK_WORKERS=4 MC_SAVE_WORKERS=1
cw4_light MC_CHUNK_WORKERS=4 MC_LIGHT_WORKERS=1
cw4_dim MC_CHUNK_WORKERS=4 MC_DIM_THREADS=1
CFG
  r=$((r + 1))
done
