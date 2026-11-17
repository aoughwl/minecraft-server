#!/bin/sh
# Chunk-border scenario on a PRIVATE server: scratch world dir, ports 25860-25864 only, never the user's instance.
#   sh tests/run_border_scenario.sh <exe> [scenario args, e.g. --mode cmd --y 100 --away 20 --pregen 6]
# Env: BORDER_DIR (default C:/m/border/w), BORDER_PORT (25860), MC_CHUNK_WORKERS (0 or 4).
# Phase 1 places and reads back after 5 s and after save-all, then stops the server over RCON; phase 2 restarts it on the same world and reads
# every cell again. Exit status 0 only when nothing is missing in either phase.
EXE="$1"
shift
[ -n "$EXE" ] && [ -f "$EXE" ] || { echo "usage: run_border_scenario.sh <server executable> [scenario args]"; exit 2; }
HERE="$(cd "$(dirname "$0")/.." && pwd -W 2>/dev/null || pwd)"
RUN="${BORDER_DIR:-C:/m/border/w}"
PORT="${BORDER_PORT:-25860}"
RCON=$((PORT + 1))
BEDROCK=$((PORT + 2))
NAME=BorderBot
export PATH="/c/msys64/ucrt64/bin:$PATH"
EXENAME="$(basename "$EXE")"
taskkill //F //IM "$EXENAME" > /dev/null 2>&1
sleep 1
rm -rf "$RUN"
mkdir -p "$RUN/data"
cd "$RUN"
"$EXE" > first.txt 2>&1 &
sleep 8
taskkill //F //IM "$EXENAME" > /dev/null 2>&1
sleep 1
sed -i "s/0.0.0.0:25565/0.0.0.0:$PORT/; s/0.0.0.0:25575/0.0.0.0:$RCON/; s/0.0.0.0:19132/0.0.0.0:$BEDROCK/" minecraft-server.toml
sed -i '/^\[networking.java\]/,/^\[/ { s/^encryption = true/encryption = false/; s/^online_mode = true/online_mode = false/ }' minecraft-server.toml
sed -i '/^\[networking.rcon\]/,/^\[/ { s/^enabled = false/enabled = true/; s/^password = ""/password = "borderpw"/ }' minecraft-server.toml
python - "$NAME" > data/ops.json <<'PY'
import hashlib, sys, uuid, json
name = sys.argv[1]
print(json.dumps([{"uuid": str(uuid.UUID(bytes=hashlib.md5(("OfflinePlayer:" + name).encode()).digest(), version=3)), "name": name, "level": 4,
                   "bypasses_player_limit": False}]))
PY
stop_server() {
  python - "$RCON" <<'PY'
import sys, socket
sys.path.insert(0, sys.argv[0] if False else __import__('os').environ.get('MCBOT_DIR', '.'))
import mcbot
s = socket.create_connection(('127.0.0.1', int(sys.argv[1])), timeout=10)
s.sendall(mcbot.rcon_packet(1, 3, 'borderpw')); mcbot.rcon_read(s)
s.sendall(mcbot.rcon_packet(2, 2, 'stop'))
PY
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do sleep 1; kill -0 $SPID 2>/dev/null || return 0; done
  kill $SPID 2>/dev/null; taskkill //F //IM "$EXENAME" > /dev/null 2>&1
}
export MCBOT_DIR="$HERE/tools"
"$EXE" > server1.txt 2>&1 &
SPID=$!
sleep 12
python "$HERE/tests/border_scenario.py" --port "$PORT" --rcon-port "$RCON" --name "$NAME" --seconds 900 --op --phase place "$@"
S1=$?
stop_server
sleep 2
"$EXE" > server2.txt 2>&1 &
SPID=$!
sleep 12
python "$HERE/tests/border_scenario.py" --port "$PORT" --rcon-port "$RCON" --name "$NAME" --seconds 600 --op --phase check "$@"
S2=$?
stop_server
echo "EXIT place=$S1 check=$S2"
[ "$S1" = 0 ] && [ "$S2" = 0 ]
