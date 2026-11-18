#!/bin/sh
# Soak for the dimension gate: one server, bot PortalA walks the overworld<->nether portal in a loop for SOAK_SECS (scenario dim_portal with
# DIM_SOAK_SECS), bot PortalB sits in the nether editing blocks for the same time. The server process's working set is sampled every
# SAMPLE_SECS into mem.csv. Server environment is the caller's (MC_DIM_THREADS=1 MC_DIM_PLAYERS_MULTI_WORLD=1 MC_THREAD_ASSERT=1 ...).
#   sh tools/run_dim_soak.sh <server exe>     PORT=25960  SCENARIO_DIR=...  SOAK_SECS=1080  SAMPLE_SECS=60
EXE="$1"
[ -n "$EXE" ] && [ -f "$EXE" ] || { echo "usage: run_dim_soak.sh <server executable>"; exit 2; }
HERE="$(cd "$(dirname "$0")/.." && pwd -W 2>/dev/null || pwd)"
RUN="${SCENARIO_DIR:-$HERE/../dim_soak_run}"
PORT="${PORT:-25960}"
SOAK_SECS="${SOAK_SECS:-1080}"
SAMPLE_SECS="${SAMPLE_SECS:-60}"
RCON=$((PORT + 1)); BEDROCK=$((PORT + 2))
ENGINE_DLL="$(cd "$HERE/../aoughwl-engine/build/dll" 2>/dev/null && pwd)"
export PATH="/c/msys64/ucrt64/bin:$ENGINE_DLL:$PATH"
rm -rf "$RUN"; mkdir -p "$RUN/data"; cd "$RUN"
"$EXE" > first.txt 2>&1 &
FIRST_PID=$!
sleep 8
taskkill //PID $FIRST_PID //F > /dev/null 2>&1; kill $FIRST_PID > /dev/null 2>&1
sleep 1
sed -i '/^\[networking.java\]/,/^\[/ { s/^encryption = true/encryption = false/; s/^online_mode = true/online_mode = false/ }' minecraft-server.toml
sed -i "s/0.0.0.0:25565/0.0.0.0:$PORT/; s/0.0.0.0:25575/0.0.0.0:$RCON/; s/0.0.0.0:19132/0.0.0.0:$BEDROCK/" minecraft-server.toml
python - > data/ops.json <<'PY'
import hashlib, uuid, json
print(json.dumps([{"uuid": str(uuid.UUID(bytes=hashlib.md5(("OfflinePlayer:" + n).encode()).digest(), version=3)), "name": n, "level": 4,
                  "bypasses_player_limit": False} for n in ("PortalA", "PortalB")]))
PY
"$EXE" > server.txt 2>&1 &
SERVER_PID=$!
sleep 12
echo "elapsed_s,working_set_mb,private_mb,threads,bots_alive" > mem.csv
T0=$(date +%s)
DIM_BOT=nether DIM_COMPANION_SECS=$((SOAK_SECS + 20)) python "$HERE/tools/mcbot.py" --port "$PORT" --name PortalB --seconds $((SOAK_SECS + 120)) --scenario dim_portal > botB.txt 2>&1 &
PB=$!
sleep 12
DIM_BOT=portal DIM_SOAK_SECS="$SOAK_SECS" python "$HERE/tools/mcbot.py" --port "$PORT" --name PortalA --seconds $((SOAK_SECS + 120)) --scenario dim_portal > botA.txt 2>&1 &
PA=$!
# sample until bot A ends
while kill -0 $PA > /dev/null 2>&1; do
  NOW=$(( $(date +%s) - T0 ))
  S=$(powershell -NoProfile -Command "\$p = Get-Process -Id $SERVER_PID -ErrorAction SilentlyContinue; if (\$p) { '{0:N0},{1:N0},{2}' -f (\$p.WorkingSet64/1MB), (\$p.PrivateMemorySize64/1MB), \$p.Threads.Count } else { 'DEAD,DEAD,DEAD' }" | tr -d '\r')
  BA=0; kill -0 $PB > /dev/null 2>&1 && BA=B; kill -0 $PA > /dev/null 2>&1 && BA="${BA}A"
  echo "$NOW,$S,$BA" >> mem.csv
  sleep "$SAMPLE_SECS"
done
wait $PA; SA=$?
wait $PB; SB=$?
STOP_SERVER=1 python "$HERE/tools/mcbot.py" --port "$PORT" --name PortalA --seconds 60 --scenario stop_server > botstop.txt 2>&1
if grep -q "STAGE play_login" botstop.txt; then echo "SERVER ALIVE after the soak (a new login worked)"; else echo "SERVER NOT ANSWERING after the soak"; fi
sleep 8
echo "=== mem.csv"; cat mem.csv
echo "=== botA (status $SA)"; grep "soak:\|portal trips\|^SCENARIO\|FAIL" botA.txt | tail -20
echo "=== botB (status $SB)"; grep "companion\|^SCENARIO\|FAIL" botB.txt | tail -5
echo "=== server gate/error lines"
grep -n -i "dimtick\|violation\|owner guard\|assert\|raised\|exception\|panic\|crash\|fatal" server.txt | head -40
kill $SERVER_PID > /dev/null 2>&1
taskkill //PID $SERVER_PID //F > /dev/null 2>&1
[ $SA -eq 0 ] && [ $SB -eq 0 ]
