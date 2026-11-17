#!/bin/sh
# Runs the server-mod scenarios (tools/mcbot_scenarios.py) against a real server in a scratch directory on a spare port.
#
#   sh tools/run_scenarios.sh <server executable> [scenario[,scenario...]|all]      e.g.  sh tools/run_scenarios.sh C:/m/srv.exe
#   WORLD=<folder>      start from an existing world folder instead of a fresh one
#   PORT=25590          the Java port (RCON takes PORT+1 and Bedrock PORT+2); never the port of an instance somebody is playing on
#   SCENARIO_DIR=...    the scratch directory (default ../scenario_run, wiped first)
#   NO_PLUGINS=1        do not install the showcase plugins (their scenarios then report INCONCLUSIVE)
#
# Exits non-zero when a scenario FAILs; INCONCLUSIVE scenarios do not fail the run.
set -e
EXE="$1"
SELECT="${2:-all}"
[ -n "$EXE" ] && [ -f "$EXE" ] || { echo "usage: run_scenarios.sh <server executable> [scenarios]"; exit 2; }
HERE="$(cd "$(dirname "$0")/.." && pwd -W 2>/dev/null || pwd)"
RUN="${SCENARIO_DIR:-$HERE/../scenario_run}"
NAME=ScenBot
PORT="${PORT:-25590}"
RCON=$((PORT + 1))
BEDROCK=$((PORT + 2))
ENGINE_DLL="$(cd "$HERE/../aoughwl-engine/build/dll" && pwd)"
export PATH="/c/msys64/ucrt64/bin:$ENGINE_DLL:$PATH"
rm -rf "$RUN"
mkdir -p "$RUN/plugins" "$RUN/data"
PLUGIN_FLAG=""
if [ -z "$NO_PLUGINS" ]; then
  cp -r "$HERE/examples/hello-world" "$RUN/plugins/hello-world"
  sh "$HERE/tools/build_plugin.sh" "$RUN/plugins/hello-world"
  PLUGIN_FLAG="--scenario-plugins"
fi
[ -n "$WORLD" ] && cp -r "$WORLD" "$RUN/world"
cd "$RUN"
echo 'print("from the file");' > snippet.js
( timeout 8 "$EXE" > first.txt 2>&1 || true )
sed -i '/^\[networking.java\]/,/^\[/ { s/^encryption = true/encryption = false/; s/^online_mode = true/online_mode = false/ }' pumpkin.toml
sed -i "s/0.0.0.0:25565/0.0.0.0:$PORT/; s/0.0.0.0:25575/0.0.0.0:$RCON/; s/0.0.0.0:19132/0.0.0.0:$BEDROCK/" pumpkin.toml
python - "$NAME" > data/ops.json <<'PY'
import hashlib, sys, uuid, json
name = sys.argv[1]
print(json.dumps([{"uuid": str(uuid.UUID(bytes=hashlib.md5(("OfflinePlayer:" + name).encode()).digest(), version=3)), "name": name, "level": 4,
                   "bypasses_player_limit": False}]))
PY
"$EXE" > server.txt 2>&1 &
SERVER_PID=$!
sleep 12
set +e
python "$HERE/tools/mcbot.py" --port "$PORT" --name "$NAME" --seconds 120 --scenario "$SELECT" $PLUGIN_FLAG
STATUS=$?
kill $SERVER_PID > /dev/null 2>&1
taskkill //PID $SERVER_PID //F > /dev/null 2>&1
exit $STATUS
