#!/bin/sh
# Builds and runs the Create-port tests that need no whole-server build:
#   sh tools/run_create_tests.sh [name ...]      names: kinetic contraption createworld (default: all)
# kinetic and contraption build in ~25 s; createworld pulls in the world and entity stack (several minutes).
# Own nimcache per test under C:/m (never wiped here), exe deleted before the build so a failed build cannot run a stale exe.
# Search paths come from aowlmony.paths (the world stack imports requests/zlib/net). No build.lock: these are small test builds, like
# src/physics/run_scenes.sh. Never installs anything, never touches a running server or game.
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TOOLCHAIN="${TOOLCHAIN:-$HERE/../toolchain/aowlmony/root/bin}"
export PATH="/c/msys64/ucrt64/bin:$PATH"
cd "$HERE" || exit 2
PATHS=""
for P in $(tr -d '\r' < aowlmony.paths); do PATHS="$PATHS -p:$P"; done
NAMES="${*:-kinetic contraption createworld}"
RC=0
for N in $NAMES; do
  F=$(ls src/mods/create/${N}test.aowl 2>/dev/null)
  [ -n "$F" ] || { echo "no test $N"; RC=2; continue; }
  EXE="C:/m/create_$N.exe"
  rm -f "$EXE"
  "$TOOLCHAIN/aowlmony.exe" c --cc:gcc --nimcache:"C:/m/create_$N" -o:"$EXE" $PATHS -p:src -p:src/mods/create "$F" > "C:/m/create_$N.log" 2>&1
  [ -f "$EXE" ] || { echo "BUILD FAILED $N"; grep -i "error" "C:/m/create_$N.log" | head -20; RC=2; continue; }
  "$EXE" || RC=1
done
exit $RC
