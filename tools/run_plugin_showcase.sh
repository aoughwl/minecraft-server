#!/bin/sh
# Runs the plugin showcase against a real server: builds examples/hello-world (aowlmony), installs it and examples/hello-world-js in
# a scratch server directory, starts the server there, and has tools/mcbot.py play with them (--engine-plugin showcase).
#
#   sh tools/run_plugin_showcase.sh <server executable>        e.g.  sh tools/run_plugin_showcase.sh C:/m/srv.exe
#
# aoe_engine.dll (tools/build_engine_dll.sh) must be on PATH or next to the executable. The scratch directory is ../showcase_run.
set -e
EXE="$1"
[ -n "$EXE" ] && [ -f "$EXE" ] || { echo "usage: run_plugin_showcase.sh <server executable>"; exit 2; }
HERE="$(cd "$(dirname "$0")/.." && pwd -W 2>/dev/null || pwd)"
RUN="${SHOWCASE_DIR:-$HERE/../showcase_run}"
NAME=ShowBot
PORT=25565
ENGINE_DLL="$(cd "$HERE/../aoughwl-engine/build/dll" && pwd)"
export PATH="/c/msys64/ucrt64/bin:$ENGINE_DLL:$PATH"
rm -rf "$RUN"
mkdir -p "$RUN/plugins" "$RUN/data"
cp -r "$HERE/examples/hello-world" "$RUN/plugins/hello-world"
cp -r "$HERE/examples/hello-world-js" "$RUN/plugins/hello-world-js"
sh "$HERE/tools/build_plugin.sh" "$RUN/plugins/hello-world"
cd "$RUN"
# first start writes pumpkin.toml; the bot logs in offline, so the Java listener must not encrypt or ask Mojang
( timeout 8 "$EXE" > first.txt 2>&1 || true )
sed -i '/^\[networking.java\]/,/^\[/ { s/^encryption = true/encryption = false/; s/^online_mode = true/online_mode = false/ }' pumpkin.toml
# the bot is an operator: the server's offline UUID is vanilla's, the MD5 of "OfflinePlayer:<name>" as a version 3 UUID
python - "$NAME" > data/ops.json <<'PY'
import hashlib, sys, uuid, json
name = sys.argv[1]
print(json.dumps([{"uuid": str(uuid.UUID(bytes=hashlib.md5(("OfflinePlayer:" + name).encode()).digest(), version=3)), "name": name, "level": 4,
                   "bypasses_player_limit": False}]))
PY
"$EXE" > server.txt 2>&1 &
sleep 12
grep -a "plugin" server.txt | tr -d '\r' | cut -c1-160 | head -8 || true
set +e
python "$HERE/tools/mcbot.py" --port "$PORT" --name "$NAME" --seconds 60 --engine-plugin showcase
STATUS=$?
if [ $STATUS -eq 0 ]; then
  # the plugin turns a client called Griefer away at login
  python "$HERE/tools/mcbot.py" --port "$PORT" --name Griefer --seconds 10 --expect-refusal "Griefers are not welcome"
  STATUS=$?
fi
taskkill //IM "$(basename "$EXE")" //F > /dev/null 2>&1
exit $STATUS
