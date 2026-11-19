#!/bin/sh
# Portal entry with the dimension gate on or off: one server, bot PortalA builds a nether portal in the overworld and walks through
# it and back (scenario dim_portal), companion PortalB sits in the nether editing blocks. Server environment is the caller's.
#   sh tools/run_dim_portal.sh <server exe>     PORT=25910  SCENARIO_DIR=...  DIM_TRIPS=2  DIM_COMPANION_SECS=90
EXE="$1"
[ -n "$EXE" ] && [ -f "$EXE" ] || { echo "usage: run_dim_portal.sh <server executable>"; exit 2; }
HERE="$(cd "$(dirname "$0")/.." && pwd -W 2>/dev/null || pwd)"
RUN="${SCENARIO_DIR:-$HERE/../dim_portal_run}"
PORT="${PORT:-25910}"
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
[ -n "$SEED" ] && sed -i "s/^seed = .*/seed = \"$SEED\"/" minecraft-server.toml
"$EXE" > server.txt 2>&1 &
SERVER_PID=$!
sleep 12
DIM_BOT=nether DIM_COMPANION_SECS="${DIM_COMPANION_SECS:-90}" python "$HERE/tools/mcbot.py" --port "$PORT" --name PortalB --seconds "${BOT_SECONDS:-150}" --scenario dim_portal > botB.txt 2>&1 &
PB=$!
sleep 12
DIM_BOT=portal python "$HERE/tools/mcbot.py" --port "$PORT" --name PortalA --seconds "${BOT_SECONDS:-150}" --scenario dim_portal > botA.txt 2>&1 &
PA=$!
wait $PA; SA=$?
wait $PB; SB=$?
STOP_SERVER=1 python "$HERE/tools/mcbot.py" --port "$PORT" --name PortalA --seconds 60 --scenario stop_server > botstop.txt 2>&1
if grep -q "STAGE play_login" botstop.txt; then echo "SERVER ALIVE after bots (a new login worked)"; else echo "SERVER NOT ANSWERING after bots"; fi
sleep 8
echo "=== botA portal (status $SA)"; tail -30 botA.txt
echo "=== botB companion (status $SB)"; tail -8 botB.txt
echo "=== server gate/error lines"
grep -n -i "dimtick\|violation\|owner guard\|assert\|raised\|exception\|error\|panic\|crash\|fatal\|portal" server.txt | head -40
kill $SERVER_PID > /dev/null 2>&1
taskkill //PID $SERVER_PID //F > /dev/null 2>&1
[ $SA -eq 0 ] && [ $SB -eq 0 ]
