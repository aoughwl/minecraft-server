#!/bin/sh
# Body manager scenario on a PRIVATE server: scratch world dir, spare ports, never the user's instance.
#   sh tests/run_body_scenario.sh C:/m/bdy3.exe
set -e
EXE="$1"
[ -n "$EXE" ] && [ -f "$EXE" ] || { echo "usage: run_body_scenario.sh <server executable>"; exit 2; }
HERE="$(cd "$(dirname "$0")/.." && pwd -W 2>/dev/null || pwd)"
RUN="${BODY_DIR:-C:/m/body_run}"
PORT="${BODY_PORT:-25811}"
RCON=$((PORT + 1))
BEDROCK=$((PORT + 2))
NAME=BodyBot
export PATH="/c/msys64/ucrt64/bin:$PATH"
rm -rf "$RUN"
mkdir -p "$RUN/data"
cd "$RUN"
( timeout 10 "$EXE" > first.txt 2>&1 || true )
sed -i "s/0.0.0.0:25565/0.0.0.0:$PORT/; s/0.0.0.0:25575/0.0.0.0:$RCON/; s/0.0.0.0:19132/0.0.0.0:$BEDROCK/" minecraft-server.toml
sed -i '/^\[networking.java\]/,/^\[/ { s/^encryption = true/encryption = false/; s/^online_mode = true/online_mode = false/ }' minecraft-server.toml
sed -i '/^\[networking.rcon\]/,/^\[/ { s/^enabled = false/enabled = true/; s/^password = ""/password = "bodypw"/ }' minecraft-server.toml
python - "$NAME" > data/ops.json <<'PY'
import hashlib, sys, uuid, json
name = sys.argv[1]
print(json.dumps([{"uuid": str(uuid.UUID(bytes=hashlib.md5(("OfflinePlayer:" + name).encode()).digest(), version=3)), "name": name, "level": 4,
                   "bypasses_player_limit": False}]))
PY
"$EXE" > server.txt 2>&1 &
SPID=$!
sleep 12
set +e
python "$HERE/tests/body_scenario.py" --port "$PORT" --rcon-port "$RCON" --name "$NAME" --seconds 150 --op
STATUS=$?
kill $SPID 2>/dev/null
taskkill //PID $SPID //F > /dev/null 2>&1
sleep 1
tail -8 "$RUN/server.txt"
exit $STATUS
