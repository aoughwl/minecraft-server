#!/bin/sh
# Phase 4 with real players in two worlds: one server, two operator bots (one stays in the overworld, one is sent to the nether), scenario
# dim_threads_two_worlds (tools/mcbot_scenarios.py). Environment of the server is whatever the caller exports (MC_DIM_THREADS, MC_THREADS, ...).
#
#   sh tools/run_dim_threads.sh <server executable>      PORT=25850  SCENARIO_DIR=...  DIM_ROUNDS=40
# Prints both bots' output, then the server's gate and error lines. Exits non-zero when a bot fails.
EXE="$1"
[ -n "$EXE" ] && [ -f "$EXE" ] || { echo "usage: run_dim_threads.sh <server executable>"; exit 2; }
HERE="$(cd "$(dirname "$0")/.." && pwd -W 2>/dev/null || pwd)"
RUN="${SCENARIO_DIR:-$HERE/../dim_run}"
PORT="${PORT:-25850}"
RCON=$((PORT + 1))
BEDROCK=$((PORT + 2))
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
                  "bypasses_player_limit": False} for n in ("DimA", "DimB")]))
PY
"$EXE" > server.txt 2>&1 &
SERVER_PID=$!
sleep 12
DIM_BOT=ow python "$HERE/tools/mcbot.py" --port "$PORT" --name DimA --seconds 240 --scenario dim_threads_two_worlds > botA.txt 2>&1 &
PA=$!
sleep 3
DIM_BOT=nether python "$HERE/tools/mcbot.py" --port "$PORT" --name DimB --seconds 240 --scenario dim_threads_two_worlds > botB.txt 2>&1 &
PB=$!
wait $PA; SA=$?
wait $PB; SB=$?
# a fresh login proves the server is alive; its /stop is the graceful path that flushes the server's buffered stdout (a kill loses the last lines)
STOP_SERVER=1 python "$HERE/tools/mcbot.py" --port "$PORT" --name DimA --seconds 60 --scenario stop_server > botstop.txt 2>&1
if grep -q "STAGE play_login" botstop.txt; then echo "SERVER ALIVE after bots (a new login worked)"; else echo "SERVER NOT ANSWERING after bots"; fi
sleep 8
echo "=== botA (status $SA)"; tail -25 botA.txt
echo "=== botB (status $SB)"; tail -25 botB.txt
echo "=== server gate/error lines"
grep -n -i "dimtick\|violation\|assert\|raised\|exception\|error\|panic\|crash\|fatal" server.txt | head -40
kill $SERVER_PID > /dev/null 2>&1
taskkill //PID $SERVER_PID //F > /dev/null 2>&1
[ $SA -eq 0 ] && [ $SB -eq 0 ]
