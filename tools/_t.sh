#!/bin/sh
# usage: tools/_t.sh <test.aowl> <tag>   builds in C:/m/fab_<tag> and runs
export PATH="/c/msys64/ucrt64/bin:$PATH"
cd "$(dirname "$0")/.."
T=$1; TAG=$2
mkdir -p C:/m 2>/dev/null
/c/Users/timbuktu/dev/toolchain/aowlmony/root/bin/aowlmony.exe c --cc:gcc --nimcache:C:/m/fab_$TAG -o:C:/m/fab_$TAG.exe -p:src -p:$(dirname $T) -p:../jwt/src -p:../requests/src -p:../zlib/src -p:../../Desktop/libs/tcp -p:../../Desktop/libs/net -p:../../Desktop/libs/tls $T 2>&1 | tail -15
[ -f C:/m/fab_$TAG.exe ] && C:/m/fab_$TAG.exe
