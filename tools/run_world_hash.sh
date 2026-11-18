#!/bin/sh
# Saved-world comparison workload: one server, one bot running scenario det_world (scripted, random-free), /save-all, /stop. The world seed is
# pinned so two runs generate the same terrain. Leaves the world folder at $SCENARIO_DIR/world for tools/hash_world.py.
#   sh tools/run_world_hash.sh <server exe>     PORT=25930  SCENARIO_DIR=...  (server env = the caller's)
EXE="$1"
[ -n "$EXE" ] && [ -f "$EXE" ] || { echo "usage: run_world_hash.sh <server executable>"; exit 2; }
HERE="$(cd "$(dirname "$0")/.." && pwd -W 2>/dev/null || pwd)"
RUN="${SCENARIO_DIR:-$HERE/../world_hash_run}"
PORT="${PORT:-25930}"
RCON=$((PORT + 1)); BEDROCK=$((PORT + 2))
ENGINE_DLL="$(cd "$HERE/../aoughwl-engine/build/dll" 2>/dev/null && pwd)"
export PATH="/c/msys64/ucrt64/bin:$ENGINE_DLL:$PATH"
rm -rf "$RUN"; mkdir -p "$RUN/data"; cd "$RUN"
"$EXE" > first.txt 2>&1 &
FIRST_PID=$!
sleep 8
taskkill //PID $FIRST_PID //F > /dev/null 2>&1; kill $FIRST_PID > /dev/null 2>&1
sleep 1
rm -rf world logs
sed -i '/^\[networking.java\]/,/^\[/ { s/^encryption = true/encryption = false/; s/^online_mode = true/online_mode = false/ }' minecraft-server.toml
sed -i "s/0.0.0.0:25565/0.0.0.0:$PORT/; s/0.0.0.0:25575/0.0.0.0:$RCON/; s/0.0.0.0:19132/0.0.0.0:$BEDROCK/" minecraft-server.toml
sed -i "s/^seed = .*/seed = \"${SEED:-424242}\"/" minecraft-server.toml
grep -n '^seed' minecraft-server.toml
python - > data/ops.json <<'PY'
import hashlib, uuid, json
print(json.dumps([{"uuid": str(uuid.UUID(bytes=hashlib.md5(("OfflinePlayer:" + n).encode()).digest(), version=3)), "name": n, "level": 4,
                  "bypasses_player_limit": False} for n in ("HashBot",)]))
PY
"$EXE" > server.txt 2>&1 &
SERVER_PID=$!
sleep 12
DET_STOP=1 python "$HERE/tools/mcbot.py" --port "$PORT" --name HashBot --seconds 400 --scenario det_world > bot.txt 2>&1
SB=$?
if [ $SB -ne 0 ]; then STOP_SERVER=1 python "$HERE/tools/mcbot.py" --port "$PORT" --name HashBot --seconds 30 --scenario stop_server > botstop.txt 2>&1; fi
sleep 10
grep "^SCENARIO\|det_world done" bot.txt | cut -c1-300
if tasklist //FI "PID eq $SERVER_PID" 2>/dev/null | grep -q "$SERVER_PID"; then echo "server still running after /stop; killing"; taskkill //PID $SERVER_PID //F > /dev/null 2>&1; fi
grep -n -i "dimtick\|violation\|owner guard\|raised\|exception\|panic\|Completed save\|has stopped" server.txt | cut -c1-200 | head
exit $SB
