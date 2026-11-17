#!/bin/sh
# Light-update scenario on a PRIVATE server: scratch dir, ports LU_PORT..LU_PORT+2 only, never the user's instance. Stops its server by PID.
#   sh tests/run_lightupdate_scenario.sh <exe>
# Env: LU_DIR (scratch dir, wiped), LU_PORT (25890), MC_CHUNK_WORKERS (0 or 4, passed through to the server).
EXE="$1"
[ -n "$EXE" ] && [ -f "$EXE" ] || { echo "usage: run_lightupdate_scenario.sh <server executable>"; exit 2; }
HERE="$(cd "$(dirname "$0")/.." && pwd -W 2>/dev/null || pwd)"
RUN="${LU_DIR:-C:/m/lightupdate/w}"
PORT="${LU_PORT:-25890}"
RCON=$((PORT + 1))
BEDROCK=$((PORT + 2))
NAME=LightBot
export PATH="/c/msys64/ucrt64/bin:$PATH"
rm -rf "$RUN"
mkdir -p "$RUN/data"
cd "$RUN"
"$EXE" > first.txt 2>&1 &
FP=$!
sleep 10
kill $FP 2>/dev/null; sleep 1; kill -9 $FP 2>/dev/null
sleep 1
sed -i "s/0.0.0.0:25565/0.0.0.0:$PORT/; s/0.0.0.0:25575/0.0.0.0:$RCON/; s/0.0.0.0:19132/0.0.0.0:$BEDROCK/" minecraft-server.toml
sed -i '/^\[networking.java\]/,/^\[/ { s/^encryption = true/encryption = false/; s/^online_mode = true/online_mode = false/ }' minecraft-server.toml
python - "$NAME" > data/ops.json <<'PY'
import hashlib, sys, uuid, json
name = sys.argv[1]
print(json.dumps([{"uuid": str(uuid.UUID(bytes=hashlib.md5(("OfflinePlayer:" + name).encode()).digest(), version=3)), "name": name, "level": 4,
                   "bypasses_player_limit": False}]))
PY
"$EXE" > server.txt 2>&1 &
SPID=$!
sleep 14
python "$HERE/tests/lightupdate_scenario.py" --port "$PORT" --name "$NAME" --seconds 120
STATUS=$?
sleep 3
python "$HERE/tests/lightupdate_storm.py" --port "$PORT" --name "$NAME" --seconds 150
STORM=$?
[ "$STATUS" = 0 ] && STATUS=$STORM
kill $SPID 2>/dev/null; sleep 1; kill -9 $SPID 2>/dev/null
echo "EXIT $STATUS (server pid $SPID stopped)"
exit $STATUS
