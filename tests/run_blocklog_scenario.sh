#!/bin/sh
# Block log scenario on a PRIVATE server: scratch world dir, spare port, its own copy of the executable's data. Never the user's instance.
#   sh tests/run_blocklog_scenario.sh C:/m/blog.exe
set -e
EXE="$1"
[ -n "$EXE" ] && [ -f "$EXE" ] || { echo "usage: run_blocklog_scenario.sh <server executable>"; exit 2; }
HERE="$(cd "$(dirname "$0")/.." && pwd -W 2>/dev/null || pwd)"
RUN="${BLOG_DIR:-C:/m/blog_run}"
PORT="${BLOG_PORT:-25789}"
NAME=BlogBot
export PATH="/c/msys64/ucrt64/bin:$PATH"
rm -rf "$RUN"
mkdir -p "$RUN/data"
cd "$RUN"
( timeout 10 "$EXE" > first.txt 2>&1 || true )
sed -i "s/^\(\s*address\s*=\s*\"[0-9.]*:\)25565\"/\1$PORT\"/" minecraft-server.toml
sed -i '/^\[networking.java\]/,/^\[/ { s/^encryption = true/encryption = false/; s/^online_mode = true/online_mode = false/ }' minecraft-server.toml
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
python "$HERE/tests/blocklog_scenario.py" --port "$PORT" --name "$NAME" --seconds 120 --op
STATUS=$?
kill $SPID 2>/dev/null
sleep 2
ls -la "$RUN"/*/blocklog "$RUN"/blocklog 2>/dev/null | head -20
exit $STATUS
