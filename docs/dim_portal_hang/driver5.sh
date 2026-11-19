#!/bin/sh
# usage: driver5.sh TAG PORT ENV=... ; one dim_portal run, result appended to C:/m3/base/summary.txt
TAG=$1; PORT=$2; shift 2
cd /c/Users/timbuktu/dev/mcs-v3
D=C:/m3/base/$TAG
env "$@" SCENARIO_DIR=$D PORT=$PORT sh tools/run_dim_portal.sh C:/m/int_cleanc.exe > /c/m3/base/$TAG.out 2>&1
rc=$?
echo "rc=$rc $TAG alive=$(grep -c 'SERVER ALIVE' /c/m3/base/$TAG.out) fail: $(grep -h -i -m3 'FAIL\|not a nether_portal\|timed out\|timeout' $D/botA.txt $D/botB.txt | tr '\n' '|' | cut -c1-300)" >> /c/m3/base/summary.txt
