#!/bin/sh
# tp_storm against one server exe: sh tools/run_tp_storm.sh <exe> <port> <label>   (copies the exe; fresh scratch dir; own pid killed only)
#   RUNS="0 0 0 0 0 0.1 0.05" gaps; BAD_HIGHER=1 adds a run whose confirm id is +5 (expected: kicked)
EXE="$1"; PORT="$2"; LABEL="$3"
HERE="$(cd "$(dirname "$0")/.." && pwd -W 2>/dev/null || pwd)"
RUN="${TP_DIR:-C:/m2/tp_$LABEL}"
RCON=$((PORT + 1)); BEDROCK=$((PORT + 2))
ENGINE_DLL="$(cd "$HERE/../aoughwl-engine/build/dll" 2>/dev/null && pwd)"
export PATH="/c/msys64/ucrt64/bin:$ENGINE_DLL:$PATH"
rm -rf "$RUN"; mkdir -p "$RUN/data"; cp "$EXE" "$RUN/srv.exe"; cd "$RUN"
( timeout 8 ./srv.exe > first.txt 2>&1 || true )
sed -i '/^\[networking.java\]/,/^\[/ { s/^encryption = true/encryption = false/; s/^online_mode = true/online_mode = false/ }' minecraft-server.toml
sed -i "s/0.0.0.0:25565/0.0.0.0:$PORT/; s/0.0.0.0:25575/0.0.0.0:$RCON/; s/0.0.0.0:19132/0.0.0.0:$BEDROCK/" minecraft-server.toml
python - > data/ops.json <<'PY'
import hashlib, uuid, json
print(json.dumps([{"uuid": str(uuid.UUID(bytes=hashlib.md5(("OfflinePlayer:X").encode()).digest(), version=3)), "name": "X", "level": 4, "bypasses_player_limit": False}]))
PY
./srv.exe > server.txt 2>&1 &
SP=$!
sleep 12
echo "server pid $SP"; netstat -ano | grep ":$PORT " | head -3
i=0
for gap in ${GAPS:-0 0 0 0 0 0 0.1 0.1 0.1 0.05 0.05 0.05}; do
  i=$((i+1))
  TP_GAP=$gap TP_N=60 python "$HERE/tools/mcbot.py" --port "$PORT" --name X --seconds 60 --scenario tp_storm > bot$i.txt 2>&1
  st=$?
  echo "run $i gap=$gap exit=$st $(grep -o 'SCENARIO tp_storm *[A-Z]*' bot$i.txt) kickedtext=$(grep -c 'kicked .* into play' bot$i.txt) lost=$(grep -c -i '10054\|connection lost' bot$i.txt) tcp26=[$(netstat -ano -p tcp | grep ":$PORT " | awk '{print $4"/"$5"/"$6}' | tr '
' ' ')]"
done
if [ -n "$BAD_HIGHER" ]; then
  TP_CONFIRM_OFFSET=5 TP_GAP=0.1 TP_N=10 python "$HERE/tools/mcbot.py" --port "$PORT" --name X --seconds 40 --scenario tp_storm > botbad.txt 2>&1
  echo "bad-higher exit=$? : $(grep -i -m3 'wrong\|kick\|disconnect\|lost\|10054' botbad.txt | tr '\n' '|')"
  grep -i -m3 "wrong teleport" server.txt
fi
echo "listener at end: $(netstat -ano -p tcp | grep ":$PORT " | head -3 | tr -s " " | tr "
" "|")"
echo "server alive: $(tasklist //FI "PID eq $SP" | grep -c srv.exe)"
kill $SP > /dev/null 2>&1; taskkill //PID $SP //F > /dev/null 2>&1
